import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T4-R02", () => {
  const inventory = createInventory();
  inventory.suspendProduct("P-003");
  const order = inventory.createOrder([
    { productId: "P-002", quantity: 1 },
    { productId: "P-003", quantity: 1 },
  ]);
  const stateBeforeConfirmation = readObservableState(inventory);

  expect(() => inventory.confirmOrder(order.orderId)).toThrowError(
    expect.objectContaining({ code: "PRODUCT_SUSPENDED" }),
  );
  expect(readObservableState(inventory)).toEqual(stateBeforeConfirmation);
  expect(inventory.getOrder(order.orderId).status).toBe("draft");
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
