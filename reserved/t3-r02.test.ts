import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T3-R02", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);
  const order = inventory.createOrder([
    { productId: "P-002", quantity: 2 },
    { productId: "P-003", quantity: 11 },
  ]);
  const stateBeforeConfirmation = readObservableState(inventory);

  expect(() => inventory.confirmOrder(order.orderId)).toThrowError(
    expect.objectContaining({ code: "INSUFFICIENT_STOCK" }),
  );
  expect.soft(readObservableState(inventory)).toEqual(stateBeforeConfirmation);
  expect(inventory.getOrder(order.orderId).status).toBe("draft");
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
