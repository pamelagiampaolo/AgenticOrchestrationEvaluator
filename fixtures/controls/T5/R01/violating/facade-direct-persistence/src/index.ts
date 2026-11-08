// Fixture violante T5-R01: InventoryManagement e' una facciata, ma il servizio interno a cui delega
// conserva i dati in collezioni proprie invece di dipendere dai contratti.
export type Product = { productId: string; name: string };
export type Order = { orderId: string };

export interface ProductRepository {
  findById(productId: string): Product | undefined;
  list(): Product[];
}
export interface InventoryRepository {
  getAvailableQuantity(productId: string): number | undefined;
  setAvailableQuantity(productId: string, availableQuantity: number): void;
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

class InventoryService {
  private readonly products = new Map<string, Product>();
  private readonly quantities = new Map<string, number>();
  private readonly orders = new Map<string, Order>();

  public product(productId: string): Product | undefined {
    return this.products.get(productId);
  }
  public quantity(productId: string): number | undefined {
    return this.quantities.get(productId);
  }
  public order(orderId: string): Order | undefined {
    return this.orders.get(orderId);
  }
}

export class InventoryManagement {
  private readonly service = new InventoryService();

  public constructor(
    _products: ProductRepository,
    _inventory: InventoryRepository,
    _orders: OrderRepository,
  ) {}

  public product(productId: string): Product | undefined {
    return this.service.product(productId);
  }
  public quantity(productId: string): number | undefined {
    return this.service.quantity(productId);
  }
  public order(orderId: string): Order | undefined {
    return this.service.order(orderId);
  }
}

export function createInventoryManagementWithRepositories(
  productRepository: ProductRepository,
  inventoryRepository: InventoryRepository,
  orderRepository: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(productRepository, inventoryRepository, orderRepository);
}
