import { expect, test } from "vitest";

import {
  createInventoryManagementWithRepositories,
  type InitialProduct,
  type Order,
  type Product,
} from "../submission/src/index.ts";

test("T5-R03", () => {
  const insufficientInventory = new InventoryDouble([
    { productId: "P-002", name: "Mouse", availableQuantity: 1 },
  ]);
  const insufficientOrders = new ReverseOrderDouble();
  const insufficient = createInventoryManagementWithRepositories(
    new ProductDouble([{ productId: "P-002", name: "Mouse" }]),
    insufficientInventory,
    insufficientOrders,
  );
  const oversized = insufficient.createOrder([
    { productId: "P-002", quantity: 2 },
  ]);

  let reportedErrorCode: unknown;
  try {
    insufficient.confirmOrder(oversized.orderId);
  } catch (error) {
    reportedErrorCode = (error as { code?: unknown }).code;
  }

  const scrambledProducts: InitialProduct[] = [
    { productId: "P-003", name: "Monitor", availableQuantity: 10 },
    { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
    { productId: "P-002", name: "Mouse", availableQuantity: 5 },
  ];
  const ordering = createInventoryManagementWithRepositories(
    new ProductDouble(scrambledProducts),
    new InventoryDouble(scrambledProducts),
    new ReverseOrderDouble(),
  );

  const productIds = ordering
    .listProducts()
    .map((product) => product.productId);
  ordering.createOrder([{ productId: "P-002", quantity: 1 }]);
  ordering.createOrder([{ productId: "P-003", quantity: 1 }]);
  ordering.createOrder([{ productId: "P-002", quantity: 1 }]);
  const orderIds = ordering.listOrders().map((order) => order.orderId);

  expect.soft(reportedErrorCode).toBe("INSUFFICIENT_STOCK");
  expect.soft(insufficientInventory.quantity("P-002")).toBe(1);
  expect.soft(insufficientOrders.order(oversized.orderId)?.status).toBe("draft");
  expect.soft(productIds).toEqual(["P-001", "P-002", "P-003"]);
  expect.soft(orderIds).toEqual(["O-001", "O-002", "O-003"]);
});

class ProductDouble {
  public constructor(private readonly values: readonly Product[]) {}

  public findById(productId: string): Product | undefined {
    const product = this.values.find((value) => value.productId === productId);
    return product === undefined ? undefined : { ...product };
  }

  public list(): Product[] {
    return this.values.map((value) => ({ ...value }));
  }
}

class InventoryDouble {
  private readonly quantities: Map<string, number>;

  public constructor(products: readonly InitialProduct[]) {
    this.quantities = new Map(
      products.map((product) => [
        product.productId,
        product.availableQuantity,
      ]),
    );
  }

  public getAvailableQuantity(productId: string): number | undefined {
    return this.quantities.get(productId);
  }

  public setAvailableQuantity(productId: string, quantity: number): void {
    this.quantities.set(productId, quantity);
  }

  public quantity(productId: string): number | undefined {
    return this.quantities.get(productId);
  }
}

class ReverseOrderDouble {
  private readonly orders = new Map<string, Order>();

  public findById(orderId: string): Order | undefined {
    return copyOrder(this.orders.get(orderId));
  }

  public list(): Order[] {
    return [...this.orders.values()].reverse().map((order) => copyOrder(order)!);
  }

  public save(order: Order): void {
    this.orders.set(order.orderId, copyOrder(order)!);
  }

  public order(orderId: string): Order | undefined {
    return copyOrder(this.orders.get(orderId));
  }
}

function copyOrder(order: Order | undefined): Order | undefined {
  return order === undefined
    ? undefined
    : {
        ...order,
        lines: order.lines.map((line) => ({ ...line })),
      };
}
