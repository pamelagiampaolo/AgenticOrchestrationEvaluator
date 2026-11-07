export type Product = { productId: string };
export type Order = { orderId: string };

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

export class InMemoryProductRepository implements ProductRepository {
  public findById(_productId: string): Product | undefined { return undefined; }
  public list(): Product[] { return []; }
}
export class InMemoryInventoryRepository implements InventoryRepository {
  public getAvailableQuantity(_productId: string): number | undefined { return undefined; }
  public setAvailableQuantity(_productId: string, _quantity: number): void {}
}
export class InMemoryOrderRepository implements OrderRepository {
  public findById(_orderId: string): Order | undefined { return undefined; }
  public list(): Order[] { return []; }
  public save(_order: Order): void {}
}

export class InventoryManagement {
  private readonly ordersById = new Map<string, Order>();

  public constructor(
    private readonly products: ProductRepository,
    private readonly inventory: InventoryRepository,
    private readonly orders: OrderRepository,
  ) {}

  public remember(order: Order): void {
    this.orders.save(order);
    this.ordersById.set(order.orderId, order);
    this.products.list();
    this.inventory.getAvailableQuantity("P-001");
  }
}

export function createInventoryManagementWithRepositories(
  products: ProductRepository,
  inventory: InventoryRepository,
  orders: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(products, inventory, orders);
}
