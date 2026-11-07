export type Product = { productId: string; name: string };
export type InitialProduct = Product & { availableQuantity: number };
export type OrderLine = { productId: string; quantity: number };
export type Order = {
  orderId: string;
  status: "draft" | "confirmed";
  lines: OrderLine[];
};

export interface ProductRepository {
  findById(productId: string): Product | undefined;
  list(): Product[];
}
export interface InventoryRepository {
  getAvailableQuantity(productId: string): number | undefined;
  setAvailableQuantity(productId: string, quantity: number): void;
}
export interface OrderRepository {
  findById(orderId: string): Order | undefined;
  list(): Order[];
  save(order: Order): void;
}

export class InventoryManagement {
  private nextOrderNumber = 1;

  public constructor(
    private readonly products: ProductRepository,
    private readonly inventory: InventoryRepository,
    private readonly orders: OrderRepository,
  ) {}

  public createOrder(lines: OrderLine[]): Order {
    for (const line of lines) {
      this.products.findById(line.productId);
    }
    const order: Order = {
      orderId: `O-${String(this.nextOrderNumber++).padStart(3, "0")}`,
      status: "draft",
      lines: lines.map((line) => ({ ...line })),
    };
    this.orders.save(order);
    return copyOrder(order);
  }

  public confirmOrder(orderId: string): Order {
    const order = this.orders.findById(orderId)!;
    for (const line of order.lines) {
      const current = this.inventory.getAvailableQuantity(line.productId)!;
      this.inventory.setAvailableQuantity(
        line.productId,
        current - line.quantity,
      );
    }
    const confirmed: Order = { ...order, status: "confirmed" };
    this.orders.save(confirmed);
    return copyOrder(confirmed);
  }
}

export function createInventoryManagementWithRepositories(
  products: ProductRepository,
  inventory: InventoryRepository,
  orders: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(products, inventory, orders);
}

function copyOrder(order: Order): Order {
  return { ...order, lines: order.lines.map((line) => ({ ...line })) };
}
