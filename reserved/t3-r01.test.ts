import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
  type OrderLine,
} from "../submission/src/index.ts";

test("T3-R01", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  const lines: OrderLine[] = [
    { productId: "P-002", quantity: 2 },
    { productId: "P-003", quantity: 1 },
    { productId: "P-002", quantity: 3 },
  ];
  const order = inventory.createOrder(lines);

  expect(inventory.confirmOrder(order.orderId)).toEqual({
    orderId: "O-001",
    status: "confirmed",
    lines,
  });
  expect(inventory.getAvailableQuantity("P-002")).toBe(0);
  expect(inventory.getAvailableQuantity("P-003")).toBe(9);
});
