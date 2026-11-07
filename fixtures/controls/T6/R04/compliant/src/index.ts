export type InitialProduct = {
  productId: string;
  name: string;
  availableQuantity: number;
};

type FulfillmentStatus =
  | "draft"
  | "waiting"
  | "partially-fulfilled"
  | "fulfilled";

type FulfillmentOrderLine = {
  productId: string;
  requestedQuantity: number;
  fulfilledQuantity: number;
  remainingQuantity: number;
};

type Order = {
  orderId: string;
  status: FulfillmentStatus;
  lines: FulfillmentOrderLine[];
};

export class InventoryManagement {
  private readonly availableQuantities: Map<string, number>;
  private readonly orders = new Map<string, Order>();

  public constructor(initialProducts: InitialProduct[]) {
    this.availableQuantities = new Map(
      initialProducts.map(({ productId, availableQuantity }) => [
        productId,
        availableQuantity,
      ]),
    );
  }

  public createOrder(
    lines: Array<{ productId: string; quantity: number }>,
  ): Order {
    const order: Order = {
      orderId: "O-001",
      status: "draft",
      lines: lines.map(({ productId, quantity }) => ({
        productId,
        requestedQuantity: quantity,
        fulfilledQuantity: 0,
        remainingQuantity: quantity,
      })),
    };
    this.orders.set(order.orderId, order);
    return copyOrder(order);
  }

  public confirmOrder(orderId: string): Order {
    return this.allocateAvailableStock(this.orders.get(orderId)!);
  }

  public fulfillOrder(orderId: string): Order {
    return this.allocateAvailableStock(this.orders.get(orderId)!);
  }

  public receiveStock(productId: string, quantity: number): number {
    const updatedQuantity = this.getAvailableQuantity(productId) + quantity;
    this.availableQuantities.set(productId, updatedQuantity);
    return updatedQuantity;
  }

  public getAvailableQuantity(productId: string): number {
    return this.availableQuantities.get(productId)!;
  }

  private allocateAvailableStock(order: Order): Order {
    for (const line of order.lines) {
      const availableQuantity = this.getAvailableQuantity(line.productId);
      const allocatedQuantity = Math.min(
        availableQuantity,
        line.remainingQuantity,
      );
      line.fulfilledQuantity += allocatedQuantity;
      line.remainingQuantity -= allocatedQuantity;
      this.availableQuantities.set(
        line.productId,
        availableQuantity - allocatedQuantity,
      );
    }

    order.status = order.lines.every((line) => line.remainingQuantity === 0)
      ? "fulfilled"
      : order.lines.some((line) => line.fulfilledQuantity > 0)
        ? "partially-fulfilled"
        : "waiting";
    return copyOrder(order);
  }
}

function copyOrder(order: Order): Order {
  return {
    ...order,
    lines: order.lines.map((line) => ({ ...line })),
  };
}
