import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const requiredContracts = new Map<string, string[]>([
  ["ProductRepository", ["findById", "list"]],
  ["InventoryRepository", ["getAvailableQuantity", "setAvailableQuantity"]],
  ["OrderRepository", ["findById", "list", "save"]],
]);
const concreteRepositories = ["InMemoryProductRepository", "InMemoryInventoryRepository", "InMemoryOrderRepository"];

test("T5-R01 application logic depends on repository contracts", () => {
  const source = readTypeScriptSources("C:/EvaluatorWork/submission/src");
  const violations: string[] = [];
  for (const [contractName, operations] of requiredContracts) {
    const body = extractDeclarationBody(source, new RegExp(`\\binterface\\s+${contractName}\\b`));
    if (body === undefined) { violations.push(`missing-contract:${contractName}`); continue; }
    for (const operation of operations) if (!new RegExp(`\\b${operation}\\s*\\(`).test(body)) violations.push(`missing-operation:${contractName}.${operation}`);
  }
  for (const implementation of concreteRepositories) {
    if (!new RegExp(`\\bclass\\s+${implementation}\\b`).test(source)) violations.push(`missing-implementation:${implementation}`);
  }
  const factory = source.match(/\bfunction\s+createInventoryManagementWithRepositories\s*\(([\s\S]*?)\)\s*:\s*InventoryManagement/);
  if (factory === null) violations.push("missing-factory");
  else for (const contractName of requiredContracts.keys()) if (!new RegExp(`:\\s*${contractName}\\b`).test(factory[1] ?? "")) violations.push(`factory-missing-contract:${contractName}`);

  const applicationBody = extractDeclarationBody(source, /\bclass\s+InventoryManagement\b/);
  if (applicationBody === undefined) violations.push("missing-application-service");
  else inspectApplicationBody(applicationBody, violations);
  const uniqueViolations = [...new Set(violations)].sort();
  writeFileSync(
    "C:/EvaluatorOutput/t5-r01-private-result.json",
    JSON.stringify({ controlId: "T5-R01", violations: uniqueViolations }),
    "utf8",
  );
  expect(uniqueViolations).toEqual([]);
});

function inspectApplicationBody(applicationBody: string, violations: string[]): void {
  const contractFields = new Map<string, string>();
  for (const contractName of requiredContracts.keys()) {
    const pattern = new RegExp(`(?:private|protected|public)\\s+(?:readonly\\s+)?(\\w+)\\s*:\\s*${contractName}\\b`, "g");
    for (const match of applicationBody.matchAll(pattern)) contractFields.set(match[1]!, contractName);
    if (![...contractFields.values()].includes(contractName)) violations.push(`missing-contract-dependency:${contractName}`);
  }
  for (const implementation of concreteRepositories) {
    if (new RegExp(`(?:private|protected|public)\\s+(?:readonly\\s+)?\\w+\\s*:\\s*${implementation}\\b`).test(applicationBody)) violations.push(`concrete-repository-dependency:${implementation}`);
    if (new RegExp(`(?:private|protected|public)\\s+(?:readonly\\s+)?\\w+\\s*(?::\\s*[^;=\\r\\n]+)?\\s*=\\s*new\\s+${implementation}\\b`).test(applicationBody)) violations.push(`concrete-repository-field:${implementation}`);
  }
  const nonConstructorBody = removeConstructorBodies(applicationBody);
  for (const fieldName of findPersistenceCollectionFields(applicationBody)) {
    if (new RegExp(`\\bthis\\s*\\.\\s*${fieldName}\\s*(?:\\.|\\[)`).test(nonConstructorBody)) violations.push(`direct-persistence-collection-access:${fieldName}`);
  }
  for (const implementation of concreteRepositories) {
    if (new RegExp(`\\bnew\\s+${implementation}\\b`).test(nonConstructorBody)) violations.push(`concrete-repository-created-in-application-method:${implementation}`);
  }
  for (const [fieldName, contractName] of contractFields) {
    for (const operation of requiredContracts.get(contractName) ?? []) {
      if (!new RegExp(`\\bthis\\s*\\.\\s*${fieldName}\\s*\\.\\s*${operation}\\s*\\(`).test(nonConstructorBody)) violations.push(`unused-contract-operation:${contractName}.${operation}`);
    }
  }
}

function readTypeScriptSources(root: string): string {
  return readdirSync(root)
    .sort()
    .flatMap(name => {
      const path = join(root, name);
      if (statSync(path).isDirectory()) return [readTypeScriptSources(path)];
      return name.endsWith(".ts") && !name.endsWith(".d.ts") ? [readFileSync(path, "utf8")] : [];
    })
    .join("\n");
}

function findPersistenceCollectionFields(classBody: string): Set<string> {
  const fields = new Set<string>();
  const declarations = classBody.matchAll(/(?:private|protected|public)\s+(?:readonly\s+)?(\w+)\s*(?::\s*([^;=]+))?(?:=\s*([^;]+))?;/g);
  for (const match of declarations) {
    const shape = `${match[2] ?? ""} ${match[3] ?? ""}`;
    const entityArray = /(?:readonly\s+)?(?:Product|InitialProduct|Order)\s*\[\]/.test(shape) || /Array\s*<\s*(?:Product|InitialProduct|Order)\s*>/.test(shape);
    const keyedPersistence = /Map\s*<\s*string\s*,\s*(?:Product|InitialProduct|Order|number)\s*>/.test(shape);
    if (entityArray || keyedPersistence) fields.add(match[1]!);
  }
  return fields;
}

function extractDeclarationBody(source: string, declaration: RegExp): string | undefined {
  const match = declaration.exec(source);
  if (match === null) return undefined;
  const opening = source.indexOf("{", match.index + match[0].length);
  const closing = opening < 0 ? -1 : findMatching(source, opening, "{", "}");
  return closing < 0 ? undefined : source.slice(opening + 1, closing);
}

function removeConstructorBodies(classBody: string): string {
  let result = classBody;
  let searchFrom = 0;
  while (true) {
    const pattern = /\bconstructor\s*\(/g;
    pattern.lastIndex = searchFrom;
    const match = pattern.exec(result);
    if (match === null) return result;
    const openingParenthesis = result.indexOf("(", match.index);
    const signatureEnd = findMatching(result, openingParenthesis, "(", ")");
    const nextBrace = result.indexOf("{", signatureEnd + 1);
    const nextSemicolon = result.indexOf(";", signatureEnd + 1);
    if (nextSemicolon >= 0 && (nextBrace < 0 || nextSemicolon < nextBrace)) { searchFrom = nextSemicolon + 1; continue; }
    if (nextBrace < 0) return result;
    const closingBrace = findMatching(result, nextBrace, "{", "}");
    if (closingBrace < 0) return result;
    result = `${result.slice(0, match.index)}${" ".repeat(closingBrace - match.index + 1)}${result.slice(closingBrace + 1)}`;
    searchFrom = match.index + 1;
  }
}

function findMatching(source: string, opening: number, open: string, close: string): number {
  let depth = 0;
  for (let index = opening; index < source.length; index++) {
    if (source[index] === open) depth++;
    if (source[index] === close && --depth === 0) return index;
  }
  return -1;
}
