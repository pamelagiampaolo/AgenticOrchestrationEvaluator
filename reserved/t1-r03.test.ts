import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T1-R03", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
  ];
  const inventory = new InventoryManagement(products);
  const expected = inventory.findProductsBelowStock(6);
  const result = inventory.findProductsBelowStock(6);

  result[0].name = "Modificato dal test";
  result.length = 0;

  expect(inventory.findProductsBelowStock(6)).toEqual(expected);
});
