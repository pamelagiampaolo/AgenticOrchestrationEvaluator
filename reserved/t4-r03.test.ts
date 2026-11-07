import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T4-R03", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  const order = inventory.createOrder([
    { productId: "P-002", quantity: 1 },
  ]);
  const confirmed = inventory.confirmOrder(order.orderId);

  inventory.suspendProduct("P-002");

  expect.soft(inventory.getOrder(order.orderId)).toEqual(confirmed);
  expect.soft(inventory.listOrders()).toContainEqual(confirmed);
  expect(inventory.getAvailableQuantity("P-002")).toBe(4);
});
