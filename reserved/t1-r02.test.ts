import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T1-R02", () => {
  const products: InitialProduct[] = [];
  const inventory = new InventoryManagement(products);

  expect(inventory.findProductsBelowStock(6)).toEqual([]);
});
