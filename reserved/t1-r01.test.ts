import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T1-R01", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);

  expect(inventory.findProductsBelowStock(5)).toEqual([
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
  ]);
});
