import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T6-R04", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
  ];
  const inventory = new InventoryManagement(products);
  const order = inventory.createOrder([
    { productId: "P-001", quantity: 6 },
  ]);

  expect(inventory.confirmOrder(order.orderId)).toEqual(
    expectedOrder("waiting", 0, 6),
  );

  expect(inventory.receiveStock("P-001", 2)).toBe(2);
  expect(inventory.fulfillOrder(order.orderId)).toEqual(
    expectedOrder("partially-fulfilled", 2, 4),
  );
  expect(inventory.getAvailableQuantity("P-001")).toBe(0);

  expect(inventory.receiveStock("P-001", 1)).toBe(1);
  expect(inventory.fulfillOrder(order.orderId)).toEqual(
    expectedOrder("partially-fulfilled", 3, 3),
  );
  expect(inventory.getAvailableQuantity("P-001")).toBe(0);

  expect(inventory.receiveStock("P-001", 3)).toBe(3);
  expect(inventory.fulfillOrder(order.orderId)).toEqual(
    expectedOrder("fulfilled", 6, 0),
  );
  expect(inventory.getAvailableQuantity("P-001")).toBe(0);
});

function expectedOrder(
  status: "waiting" | "partially-fulfilled" | "fulfilled",
  fulfilledQuantity: number,
  remainingQuantity: number,
) {
  return {
    orderId: "O-001",
    status,
    lines: [
      {
        productId: "P-001",
        requestedQuantity: 6,
        fulfilledQuantity,
        remainingQuantity,
      },
    ],
  };
}
