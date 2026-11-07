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

function inspectSources(sourceFiles: readonly ts.SourceFile[]): string[] {
  const violations: string[] = [];
  const declarations = collectNamedDeclarations(sourceFiles);

  inspectContracts(declarations.interfaces, violations);
  inspectConcreteRepositories(declarations.classes, violations);
  inspectFactory(sourceFiles, violations);

  const applicationService = declarations.classes.get("InventoryManagement");
  if (applicationService === undefined) {
    violations.push("missing-application-service");
  } else {
    inspectApplicationService(applicationService, violations);
  }

  return [...new Set(violations)].sort();
}

function inspectContracts(
  interfaces: ReadonlyMap<string, ts.InterfaceDeclaration>,
  violations: string[],
): void {
  for (const [contractName, requiredOperations] of requiredContracts) {
    const contract = interfaces.get(contractName);
    if (contract === undefined) {
      violations.push(`missing-contract:${contractName}`);
      continue;
    }

    const operations = new Set(
      contract.members
        .filter(isCallableInterfaceMember)
        .map((member) => member.name)
        .filter(ts.isIdentifier)
        .map((name) => name.text),
    );
    for (const operation of requiredOperations) {
      if (!operations.has(operation)) {
        violations.push(`missing-operation:${contractName}.${operation}`);
      }
    }
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

  if (typeReferenceName(factory.returnType) !== "InventoryManagement") {
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

function inspectApplicationService(
  applicationService: ts.ClassDeclaration,
  violations: string[],
): void {
  const dependencyTypes = new Set<string>();

  for (const member of applicationService.members) {
    if (ts.isPropertyDeclaration(member)) {
      inspectStateMember(member.name, member.type, member.initializer, violations);
      addRepositoryDependency(member.type, dependencyTypes);
      continue;
    }

    if (ts.isConstructorDeclaration(member)) {
      for (const parameter of member.parameters) {
        if (!isParameterProperty(parameter)) {
          continue;
        }
        inspectStateMember(parameter.name, parameter.type, parameter.initializer, violations);
        addRepositoryDependency(parameter.type, dependencyTypes);
      }
      continue;
    }

    inspectForbiddenConcreteConstruction(member, violations);
  }

  for (const contractName of requiredContracts.keys()) {
    if (!dependencyTypes.has(contractName)) {
      violations.push(`missing-contract-dependency:${contractName}`);
    }
  }
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

function collectNamedDeclarations(sourceFiles: readonly ts.SourceFile[]): {
  interfaces: Map<string, ts.InterfaceDeclaration>;
  classes: Map<string, ts.ClassDeclaration>;
} {
  const interfaces = new Map<string, ts.InterfaceDeclaration>();
  const classes = new Map<string, ts.ClassDeclaration>();

  for (const sourceFile of sourceFiles) {
    visit(sourceFile);
  }

  return { interfaces, classes };

  function visit(node: ts.Node): void {
    if (ts.isInterfaceDeclaration(node)) {
      interfaces.set(node.name.text, node);
    } else if (ts.isClassDeclaration(node) && node.name !== undefined) {
      classes.set(node.name.text, node);
    }
    node.forEachChild(visit);
  }
}
