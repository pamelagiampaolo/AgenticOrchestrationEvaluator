import * as ts from "typescript/unstable/ast";
import { API } from "typescript/unstable/sync";
import { expect, test } from "vitest";

const requiredContracts = new Map<string, readonly string[]>([
  ["ProductRepository", ["findById", "list"]],
  ["InventoryRepository", ["getAvailableQuantity", "setAvailableQuantity"]],
  ["OrderRepository", ["findById", "list", "save"]],
]);

const concreteRepositories = new Set([
  "InMemoryProductRepository",
  "InMemoryInventoryRepository",
  "InMemoryOrderRepository",
]);

test("T5-R01 application logic depends on repository contracts", () => {
  const api = new API();
  const submissionRoot = decodeURIComponent(
    new URL("../submission/", import.meta.url).pathname,
  )
    .replace(/^\/([A-Za-z]:)/, "$1")
    .replace(/\/$/, "");
  const configFile = `${submissionRoot}/tsconfig.json`;

  try {
    const snapshot = api.updateSnapshot({ openProjects: [configFile] });
    const project = snapshot.getProjects()[0];
    if (project === undefined) {
      throw new Error("TypeScript did not load the submission project");
    }

    const sourceFiles = project.program
      .getSourceFileNames()
      .filter(
        (path) =>
          path.replaceAll("\\", "/").startsWith(`${submissionRoot}/src/`) &&
          /\.tsx?$/.test(path) &&
          !path.endsWith(".d.ts"),
      )
      .map((path) => project.program.getSourceFile(path))
      .filter((sourceFile): sourceFile is ts.SourceFile => sourceFile !== undefined);

    expect(inspectSources(sourceFiles)).toEqual([]);
    snapshot.dispose();
  } finally {
    api.close();
  }
});

type Declarations = {
  interfaces: Map<string, ts.InterfaceDeclaration>;
  typeAliases: Map<string, ts.TypeAliasDeclaration>;
  classes: Map<string, ts.ClassDeclaration>;
};

function inspectSources(sourceFiles: readonly ts.SourceFile[]): string[] {
  const violations: string[] = [];
  const declarations = collectNamedDeclarations(sourceFiles);

  inspectContracts(declarations, violations);
  inspectConcreteRepositories(declarations.classes, violations);
  inspectFactory(sourceFiles, violations);

  const applicationService = declarations.classes.get("InventoryManagement");
  if (applicationService === undefined) {
    violations.push("missing-application-service");
  } else {
    inspectApplicationService(applicationService, declarations.classes, violations);
  }

  return [...new Set(violations)].sort();
}

// Un contratto puo' essere un'interfaccia (anche con operazioni ereditate tramite extends da
// interfacce o alias del progetto) oppure un alias di tipo oggetto, eventualmente un'intersezione.
function inspectContracts(declarations: Declarations, violations: string[]): void {
  for (const [contractName, requiredOperations] of requiredContracts) {
    const operations = contractOperations(contractName, declarations, new Set());
    if (operations === undefined) {
      violations.push(`missing-contract:${contractName}`);
      continue;
    }

    for (const operation of requiredOperations) {
      if (!operations.has(operation)) {
        violations.push(`missing-operation:${contractName}.${operation}`);
      }
    }
  }
}

function contractOperations(
  name: string,
  declarations: Declarations,
  visited: Set<string>,
): Set<string> | undefined {
  if (visited.has(name)) {
    return new Set();
  }
  visited.add(name);

  const contractInterface = declarations.interfaces.get(name);
  if (contractInterface !== undefined) {
    const operations = callableMemberNames(contractInterface.members);
    for (const clause of contractInterface.heritageClauses ?? []) {
      if (clause.token !== ts.SyntaxKind.ExtendsKeyword) {
        continue;
      }
      for (const inherited of clause.types) {
        if (ts.isIdentifier(inherited.expression)) {
          mergeInto(operations, contractOperations(inherited.expression.text, declarations, visited));
        }
      }
    }
    return operations;
  }

  const alias = declarations.typeAliases.get(name);
  if (alias !== undefined) {
    return typeNodeOperations(alias.type, declarations, visited);
  }

  return undefined;
}

function typeNodeOperations(
  type: ts.TypeNode,
  declarations: Declarations,
  visited: Set<string>,
): Set<string> {
  if (ts.isTypeLiteralNode(type)) {
    return callableMemberNames(type.members);
  }
  if (ts.isParenthesizedTypeNode(type)) {
    return typeNodeOperations(type.type, declarations, visited);
  }
  const operations = new Set<string>();
  if (ts.isIntersectionTypeNode(type)) {
    for (const part of type.types) {
      mergeInto(operations, typeNodeOperations(part, declarations, visited));
    }
    return operations;
  }
  const referenced = typeReferenceName(type);
  if (referenced !== undefined) {
    mergeInto(operations, contractOperations(referenced, declarations, visited));
  }
  return operations;
}

function callableMemberNames(members: readonly ts.TypeElement[]): Set<string> {
  return new Set(
    members
      .filter(isCallableInterfaceMember)
      .map((member) => member.name)
      .filter(ts.isIdentifier)
      .map((name) => name.text),
  );
}

function mergeInto(target: Set<string>, source: ReadonlySet<string> | undefined): void {
  for (const value of source ?? []) {
    target.add(value);
  }
}

function isCallableInterfaceMember(
  member: ts.TypeElement,
): member is (ts.MethodSignatureDeclaration | ts.PropertySignatureDeclaration) & {
  name: ts.PropertyName;
} {
  if (ts.isMethodSignatureDeclaration(member)) {
    return member.name !== undefined;
  }

  return (
    ts.isPropertySignatureDeclaration(member) &&
    member.name !== undefined &&
    member.type !== undefined &&
    ts.isFunctionTypeNode(member.type)
  );
}

function inspectConcreteRepositories(
  classes: ReadonlyMap<string, ts.ClassDeclaration>,
  violations: string[],
): void {
  for (const repositoryName of concreteRepositories) {
    if (!classes.has(repositoryName)) {
      violations.push(`missing-implementation:${repositoryName}`);
    }
  }
}

function inspectFactory(
  sourceFiles: readonly ts.SourceFile[],
  violations: string[],
): void {
  const factory = findFactory(sourceFiles);
  if (factory === undefined) {
    violations.push("missing-factory");
    return;
  }

  const expectedParameterTypes = [...requiredContracts.keys()];
  if (factory.parameters.length !== expectedParameterTypes.length) {
    violations.push("factory-parameter-count");
  }

  expectedParameterTypes.forEach((expectedType, index) => {
    const parameter = factory.parameters[index];
    if (parameter === undefined || typeReferenceName(parameter.type) !== expectedType) {
      violations.push(`factory-missing-contract:${expectedType}`);
    }
  });

  // Senza annotazione il tipo e' inferito (e verificato dai test pubblici); si segnala soltanto un
  // tipo di ritorno dichiarato diverso.
  if (
    factory.returnType !== undefined &&
    typeReferenceName(factory.returnType) !== "InventoryManagement"
  ) {
    violations.push("factory-return-type");
  }
}

type FactoryShape = {
  parameters: readonly ts.ParameterDeclaration[];
  returnType: ts.TypeNode | undefined;
};

function findFactory(sourceFiles: readonly ts.SourceFile[]): FactoryShape | undefined {
  for (const sourceFile of sourceFiles) {
    for (const statement of sourceFile.statements) {
      if (
        ts.isFunctionDeclaration(statement) &&
        statement.name?.text === "createInventoryManagementWithRepositories"
      ) {
        return { parameters: statement.parameters, returnType: statement.type };
      }

      if (!ts.isVariableStatement(statement)) {
        continue;
      }

      for (const declaration of statement.declarationList.declarations) {
        if (
          ts.isIdentifier(declaration.name) &&
          declaration.name.text === "createInventoryManagementWithRepositories" &&
          declaration.initializer !== undefined &&
          (ts.isArrowFunction(declaration.initializer) ||
            ts.isFunctionExpression(declaration.initializer))
        ) {
          return {
            parameters: declaration.initializer.parameters,
            returnType: declaration.initializer.type,
          };
        }
      }
    }
  }

  return undefined;
}

// La logica applicativa e' InventoryManagement piu le classi del progetto a cui delega tramite i
// propri campi (per esempio una facciata con un servizio interno): a tutte si applicano le stesse
// regole, e le dipendenze dai contratti possono trovarsi in una qualunque di esse.
function inspectApplicationService(
  applicationService: ts.ClassDeclaration,
  classes: ReadonlyMap<string, ts.ClassDeclaration>,
  violations: string[],
): void {
  const dependencyTypes = new Set<string>();
  const inspected = new Set<ts.ClassDeclaration>();
  const pending = [applicationService];

  while (pending.length > 0) {
    const current = pending.pop()!;
    if (inspected.has(current)) {
      continue;
    }
    inspected.add(current);
    for (const delegateName of inspectApplicationClass(current, dependencyTypes, violations)) {
      const delegate = classes.get(delegateName);
      if (delegate !== undefined && !concreteRepositories.has(delegateName)) {
        pending.push(delegate);
      }
    }
  }

  for (const contractName of requiredContracts.keys()) {
    if (!dependencyTypes.has(contractName)) {
      violations.push(`missing-contract-dependency:${contractName}`);
    }
  }
}

// Ispeziona una classe della logica applicativa e restituisce i nomi dei tipi dei suoi campi di
// istanza, per seguire le deleghe. I membri statici non sono stato dell'istanza: una costante
// statica non e' un archivio, e un metodo statico che crea i repository in memoria fa parte della
// composizione predefinita come il costruttore.
function inspectApplicationClass(
  applicationClass: ts.ClassDeclaration,
  dependencyTypes: Set<string>,
  violations: string[],
): string[] {
  const fieldTypes: string[] = [];
  const recordField = (type: ts.TypeNode | undefined, initializer: ts.Expression | undefined) => {
    const name = typeReferenceName(type) ?? constructedClassName(initializer);
    if (name !== undefined) {
      fieldTypes.push(name);
    }
  };

  for (const member of applicationClass.members) {
    if (isStaticMember(member)) {
      continue;
    }

    if (ts.isPropertyDeclaration(member)) {
      inspectStateMember(member.name, member.type, member.initializer, violations);
      addRepositoryDependency(member.type, dependencyTypes);
      recordField(member.type, member.initializer);
      continue;
    }

    if (ts.isConstructorDeclaration(member)) {
      for (const parameter of member.parameters) {
        if (!isParameterProperty(parameter)) {
          continue;
        }
        inspectStateMember(parameter.name, parameter.type, parameter.initializer, violations);
        addRepositoryDependency(parameter.type, dependencyTypes);
        recordField(parameter.type, parameter.initializer);
      }
      continue;
    }

    inspectForbiddenConcreteConstruction(member, violations);
  }

  return fieldTypes;
}

function isStaticMember(member: ts.ClassElement): boolean {
  if (ts.isClassStaticBlockDeclaration(member)) {
    return true;
  }
  const modifiers = (member as { modifiers?: readonly ts.Node[] }).modifiers;
  return modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.StaticKeyword) ?? false;
}

function constructedClassName(initializer: ts.Expression | undefined): string | undefined {
  if (
    initializer !== undefined &&
    ts.isNewExpression(initializer) &&
    ts.isIdentifier(initializer.expression)
  ) {
    return initializer.expression.text;
  }
  return undefined;
}

function inspectStateMember(
  name: ts.BindingName | ts.PropertyName,
  type: ts.TypeNode | undefined,
  initializer: ts.Expression | undefined,
  violations: string[],
): void {
  const memberName = ts.isIdentifier(name) ? name.text : name.getText();
  const referencedType = typeReferenceName(type);

  if (referencedType !== undefined && concreteRepositories.has(referencedType)) {
    violations.push(`concrete-repository-dependency:${referencedType}`);
  }

  if (isPersistentCollection(type, initializer)) {
    violations.push(`direct-persistence-field:${memberName}`);
  }
}

function isPersistentCollection(
  type: ts.TypeNode | undefined,
  initializer: ts.Expression | undefined,
): boolean {
  if (type !== undefined) {
    if (ts.isArrayTypeNode(type) || ts.isTupleTypeNode(type)) {
      return true;
    }

    const collectionType = typeReferenceName(type);
    if (
      collectionType === "Map" ||
      collectionType === "Set" ||
      collectionType === "Array" ||
      collectionType === "ReadonlyArray"
    ) {
      return true;
    }
  }

  if (initializer === undefined) {
    return false;
  }

  if (ts.isArrayLiteralExpression(initializer)) {
    return true;
  }

  return (
    ts.isNewExpression(initializer) &&
    ts.isIdentifier(initializer.expression) &&
    (initializer.expression.text === "Map" ||
      initializer.expression.text === "Set" ||
      initializer.expression.text === "Array")
  );
}

function inspectForbiddenConcreteConstruction(
  node: ts.Node,
  violations: string[],
): void {
  visit(node);

  function visit(current: ts.Node): void {
    if (
      ts.isNewExpression(current) &&
      ts.isIdentifier(current.expression) &&
      concreteRepositories.has(current.expression.text)
    ) {
      violations.push(
        `concrete-repository-created-in-application-method:${current.expression.text}`,
      );
    }
    current.forEachChild(visit);
  }
}

function addRepositoryDependency(
  type: ts.TypeNode | undefined,
  dependencyTypes: Set<string>,
): void {
  const referencedType = typeReferenceName(type);
  if (referencedType !== undefined && requiredContracts.has(referencedType)) {
    dependencyTypes.add(referencedType);
  }
}

function isParameterProperty(parameter: ts.ParameterDeclaration): boolean {
  return (
    parameter.modifiers?.some(
      (modifier) =>
        modifier.kind === ts.SyntaxKind.PublicKeyword ||
        modifier.kind === ts.SyntaxKind.ProtectedKeyword ||
        modifier.kind === ts.SyntaxKind.PrivateKeyword ||
        modifier.kind === ts.SyntaxKind.ReadonlyKeyword,
    ) ?? false
  );
}

function typeReferenceName(type: ts.TypeNode | undefined): string | undefined {
  if (type === undefined || !ts.isTypeReferenceNode(type)) {
    return undefined;
  }

  return ts.isIdentifier(type.typeName) ? type.typeName.text : type.typeName.right.text;
}

function collectNamedDeclarations(sourceFiles: readonly ts.SourceFile[]): Declarations {
  const interfaces = new Map<string, ts.InterfaceDeclaration>();
  const typeAliases = new Map<string, ts.TypeAliasDeclaration>();
  const classes = new Map<string, ts.ClassDeclaration>();

  for (const sourceFile of sourceFiles) {
    visit(sourceFile);
  }

  return { interfaces, typeAliases, classes };

  function visit(node: ts.Node): void {
    if (ts.isInterfaceDeclaration(node)) {
      interfaces.set(node.name.text, node);
    } else if (ts.isTypeAliasDeclaration(node)) {
      typeAliases.set(node.name.text, node);
    } else if (ts.isClassDeclaration(node) && node.name !== undefined) {
      classes.set(node.name.text, node);
    }
    node.forEachChild(visit);
  }
}
