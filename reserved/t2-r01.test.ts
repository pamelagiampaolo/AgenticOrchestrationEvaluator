import { expect, test } from "vitest";

import {
  InventoryManagement,
  type InitialProduct,
} from "../submission/src/index.ts";

test("T2-R01", () => {
  const products: InitialProduct[] = [
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
  ];
  const inventory = new InventoryManagement(products);

  for (const quantity of [-1, 1.5]) {
    const stateBefore = readObservableState(inventory);

    expect(() => inventory.receiveStock("P-002", quantity)).toThrowError(
      expect.objectContaining({ code: "INVALID_QUANTITY" }),
    );
    expect.soft(readObservableState(inventory)).toEqual(stateBefore);
  }
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
