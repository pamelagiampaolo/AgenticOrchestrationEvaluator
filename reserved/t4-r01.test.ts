import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T4-R01", () => {
  const inventory = createInventory();
  const stateBefore = readObservableState(inventory);

  expect(() => inventory.suspendProduct("P-999")).toThrowError(
    expect.objectContaining({ code: "PRODUCT_NOT_FOUND" }),
  );
  expect(readObservableState(inventory)).toEqual(stateBefore);
});

function createInventory(): InventoryManagement {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  return new InventoryManagement(products);
}

function readObservableState(inventory: InventoryManagement) {
  const products = inventory.listProducts();
  return {
    products,
    productsWithStatus: inventory.listProductsWithStatus(),
    availableQuantities: products.map(({ productId }) => ({
      productId,
      availableQuantity: inventory.getAvailableQuantity(productId),
    })),
    orders: inventory.listOrders(),
  };
}
