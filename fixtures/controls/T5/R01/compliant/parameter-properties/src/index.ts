export type Product = { productId: string };
export type Order = { orderId: string };

export interface ProductRepository {
  findById: (productId: string) => Product | undefined;
  list: () => Product[];
}
export interface InventoryRepository {
  getAvailableQuantity: (productId: string) => number | undefined;
  setAvailableQuantity: (productId: string, quantity: number) => void;
}
export interface OrderRepository {
  findById: (orderId: string) => Order | undefined;
  list: () => Order[];
  save: (order: Order) => void;
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
  public constructor(
    private readonly catalog: ProductRepository,
    private readonly stock: InventoryRepository,
    private readonly orderStore: OrderRepository,
  ) {}

  public dependenciesAreUsable(): boolean {
    this.catalog.list();
    this.stock.getAvailableQuantity("P-001");
    this.orderStore.list();
    return true;
  }
}

export const createInventoryManagementWithRepositories = (
  products: ProductRepository,
  inventory: InventoryRepository,
  orders: OrderRepository,
): InventoryManagement => new InventoryManagement(products, inventory, orders);
