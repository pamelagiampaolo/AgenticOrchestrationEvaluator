import type { InitialProduct, Order, Product } from "../submission/src/index.ts";
import { createInventoryManagementWithRepositories } from "../submission/src/index.ts";
import { writeFileSync } from "node:fs";

const standard: InitialProduct[] = [{ productId: "P-001", name: "Keyboard", availableQuantity: 0 }, { productId: "P-002", name: "Mouse", availableQuantity: 5 }, { productId: "P-003", name: "Monitor", availableQuantity: 10 }];
const privateResults: Record<string, Record<string, boolean>> = {};

afterAll(() => {
  writeFileSync("C:/EvaluatorOutput/t5-r02-r03-private-result.json", JSON.stringify(privateResults), "utf8");
});

test("T5-R02-shared", () => {
  const products = new ProductDouble(standard);
  const inventory = new InventoryDouble(standard);
  const orders = new ReverseOrderDouble();
  const system = createInventoryManagementWithRepositories(products, inventory, orders);
  const confirmed = system.confirmOrder(system.createOrder([{ productId: "P-002", quantity: 2 }]).orderId);
  const expectedOrder = { orderId: "O-001", status: "confirmed", lines: [{ productId: "P-002", quantity: 2 }] };
  privateResults.R02 = {
    orderConfirmed: JSON.stringify(confirmed) === JSON.stringify(expectedOrder),
    replacementStockUpdated: inventory.quantity("P-002") === 3,
    replacementOrderStored: JSON.stringify(orders.order("O-001")) === JSON.stringify(confirmed),
    allReplacementsUsed: products.used && inventory.used && orders.used,
  };
  expect.soft(confirmed).toEqual(expectedOrder);
  expect.soft(inventory.quantity("P-002")).toBe(3);
  expect.soft(orders.order("O-001")).toEqual(confirmed);
  expect.soft([products.used, inventory.used, orders.used]).toEqual([true, true, true]);
});

test("T5-R03", () => {
  const insufficientInventory = new InventoryDouble([{ productId: "P-002", name: "Mouse", availableQuantity: 1 }]);
  const insufficientOrders = new ReverseOrderDouble();
  const insufficient = createInventoryManagementWithRepositories(new ProductDouble([{ productId: "P-002", name: "Mouse" }]), insufficientInventory, insufficientOrders);
  const oversized = insufficient.createOrder([{ productId: "P-002", quantity: 2 }]);
  let insufficientStockReported = false;
  try { insufficient.confirmOrder(oversized.orderId); } catch (error) { insufficientStockReported = (error as { code?: unknown }).code === "INSUFFICIENT_STOCK"; }

  const scrambled: InitialProduct[] = [{ productId: "P-003", name: "Monitor", availableQuantity: 10 }, { productId: "P-001", name: "Keyboard", availableQuantity: 0 }, { productId: "P-002", name: "Mouse", availableQuantity: 5 }];
  const ordering = createInventoryManagementWithRepositories(new ProductDouble(scrambled), new InventoryDouble(scrambled), new ReverseOrderDouble());
  const productIds = ordering.listProducts().map(product => product.productId);
  ordering.createOrder([{ productId: "P-002", quantity: 1 }]);
  ordering.createOrder([{ productId: "P-003", quantity: 1 }]);
  ordering.createOrder([{ productId: "P-002", quantity: 1 }]);
  const orderIds = ordering.listOrders().map(order => order.orderId);
  privateResults.R03 = {
    insufficientStockReported,
    stockUnchanged: insufficientInventory.quantity("P-002") === 1,
    orderRemainsDraft: insufficientOrders.order(oversized.orderId)?.status === "draft",
    productsSorted: JSON.stringify(productIds) === JSON.stringify(["P-001", "P-002", "P-003"]),
    ordersSorted: JSON.stringify(orderIds) === JSON.stringify(["O-001", "O-002", "O-003"]),
  };
  expect.soft(insufficientStockReported).toBe(true);
  expect.soft(insufficientInventory.quantity("P-002")).toBe(1);
  expect.soft(insufficientOrders.order(oversized.orderId)?.status).toBe("draft");
  expect.soft(productIds).toEqual(["P-001", "P-002", "P-003"]);
  expect.soft(orderIds).toEqual(["O-001", "O-002", "O-003"]);
});

class ProductDouble { public used = false; public constructor(private readonly values: readonly Product[]) {} public findById(id: string): Product | undefined { this.used = true; return this.values.find(value => value.productId === id); } public list(): Product[] { this.used = true; return this.values.map(value => ({ ...value })); } }
class InventoryDouble { public used = false; private readonly values: Map<string, number>; public constructor(products: readonly InitialProduct[]) { this.values = new Map(products.map(product => [product.productId, product.availableQuantity])); } public getAvailableQuantity(id: string): number | undefined { this.used = true; return this.values.get(id); } public setAvailableQuantity(id: string, quantity: number): void { this.used = true; this.values.set(id, quantity); } public quantity(id: string): number | undefined { return this.values.get(id); } }
class ReverseOrderDouble { public used = false; private readonly values = new Map<string, Order>(); public findById(id: string): Order | undefined { this.used = true; return this.values.get(id); } public list(): Order[] { this.used = true; return [...this.values.values()].reverse(); } public save(order: Order): void { this.used = true; this.values.set(order.orderId, structuredClone(order)); } public order(id: string): Order | undefined { return this.values.get(id); } }
