import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T2-R02", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventoryA = new InventoryManagement(products);
  const inventoryB = new InventoryManagement(products);
  const stateBeforeB = readObservableState(inventoryB);

  expect(inventoryA.receiveStock("P-002", 2)).toBe(7);
  expect(readObservableState(inventoryB)).toEqual(stateBeforeB);
});

function readObservableState(inventory: InventoryManagement) {
  const products = inventory.listProducts();

  return {
    products,
    availableQuantities: products.map(({ productId }) => ({
      productId,
      availableQuantity: inventory.getAvailableQuantity(productId),
    })),
    orders: inventory.listOrders(),
  };
}
