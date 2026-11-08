// Sonda T5-R01: InventoryManagement e' una facciata che delega a un servizio interno; e' il
// servizio a dipendere dai contratti.
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

export class InventoryManagement {
  private readonly service: InventoryService;

  public constructor(
    products: ProductRepository,
    inventory: InventoryRepository,
    orders: OrderRepository,
  ) {
    this.service = new InventoryService(products, inventory, orders);
  }

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
