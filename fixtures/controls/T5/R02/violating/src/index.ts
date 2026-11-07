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

const hiddenProducts: InitialProduct[] = [
  { productId: "P-001", name: "Tastiera", availableQuantity: 0 },
  { productId: "P-002", name: "Mouse", availableQuantity: 5 },
  { productId: "P-003", name: "Monitor", availableQuantity: 10 },
];

export function createInventoryManagementWithRepositories(
  _products: ProductRepository,
  _inventory: InventoryRepository,
  _orders: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(
    new HiddenProductRepository(hiddenProducts),
    new HiddenInventoryRepository(hiddenProducts),
    new HiddenOrderRepository(),
  );
}

class HiddenProductRepository implements ProductRepository {
  public constructor(private readonly values: readonly Product[]) {}
  public findById(productId: string): Product | undefined {
    return this.values.find((value) => value.productId === productId);
  }
  public list(): Product[] { return this.values.map((value) => ({ ...value })); }
}

class HiddenInventoryRepository implements InventoryRepository {
  private readonly values: Map<string, number>;
  public constructor(products: readonly InitialProduct[]) {
    this.values = new Map(
      products.map((product) => [product.productId, product.availableQuantity]),
    );
  }
  public getAvailableQuantity(productId: string): number | undefined {
    return this.values.get(productId);
  }
  public setAvailableQuantity(productId: string, quantity: number): void {
    this.values.set(productId, quantity);
  }
}

class HiddenOrderRepository implements OrderRepository {
  private readonly values = new Map<string, Order>();
  public findById(orderId: string): Order | undefined {
    return this.values.get(orderId);
  }
  public list(): Order[] { return [...this.values.values()]; }
  public save(order: Order): void { this.values.set(order.orderId, copyOrder(order)); }
}

function copyOrder(order: Order): Order {
  return { ...order, lines: order.lines.map((line) => ({ ...line })) };
}
