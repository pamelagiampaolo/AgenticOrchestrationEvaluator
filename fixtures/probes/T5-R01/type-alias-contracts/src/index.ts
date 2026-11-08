// Sonda T5-R01: contratti dichiarati come alias di tipo invece che come interfacce.
export type Product = { productId: string; name: string };
export type Order = { orderId: string };

export type ProductRepository = {
  findById(productId: string): Product | undefined;
  list(): Product[];
};
export type InventoryRepository = {
  getAvailableQuantity(productId: string): number | undefined;
  setAvailableQuantity(productId: string, availableQuantity: number): void;
};
export type OrderRepository = {
  findById(orderId: string): Order | undefined;
  list(): Order[];
  save(order: Order): void;
};

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
    private readonly products: ProductRepository,
    private readonly inventory: InventoryRepository,
    private readonly orders: OrderRepository,
  ) {}

  public product(productId: string): Product | undefined {
    return this.products.findById(productId);
  }
  public quantity(productId: string): number | undefined {
    return this.inventory.getAvailableQuantity(productId);
  }
  public order(orderId: string): Order | undefined {
    return this.orders.findById(orderId);
  }
}

export function createInventoryManagementWithRepositories(
  productRepository: ProductRepository,
  inventoryRepository: InventoryRepository,
  orderRepository: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(productRepository, inventoryRepository, orderRepository);
}
