// Fixture conforme T5-R01: il costruttore originale (initialProducts) resta; la composizione predefinita con
// i repository in memoria e' in un metodo statico privato invece che nel costruttore.
export type Product = { productId: string; name: string };
export type InitialProduct = Product & { availableQuantity: number };
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
  public constructor(private readonly initialProducts: readonly Product[]) {}
  public findById(productId: string): Product | undefined {
    const product = this.initialProducts.find((candidate) => candidate.productId === productId);
    return product === undefined ? undefined : { ...product };
  }
  public list(): Product[] { return this.initialProducts.map((product) => ({ ...product })); }
}
export class InMemoryInventoryRepository implements InventoryRepository {
  public constructor(private readonly initialProducts: readonly InitialProduct[]) {}
  public getAvailableQuantity(productId: string): number | undefined {
    return this.initialProducts.find((candidate) => candidate.productId === productId)?.availableQuantity;
  }
  public setAvailableQuantity(_productId: string, _quantity: number): void {}
}
export class InMemoryOrderRepository implements OrderRepository {
  public findById(_orderId: string): Order | undefined { return undefined; }
  public list(): Order[] { return []; }
  public save(_order: Order): void {}
}

type Repositories = {
  products: ProductRepository;
  inventory: InventoryRepository;
  orders: OrderRepository;
};

export class InventoryManagement {
  private readonly products: ProductRepository;
  private readonly inventory: InventoryRepository;
  private readonly orders: OrderRepository;

  public constructor(initialProducts: InitialProduct[], repositories?: Repositories) {
    const selected = repositories ?? InventoryManagement.defaultRepositories(initialProducts);
    this.products = selected.products;
    this.inventory = selected.inventory;
    this.orders = selected.orders;
  }

  private static defaultRepositories(initialProducts: InitialProduct[]): Repositories {
    return {
      products: new InMemoryProductRepository(initialProducts),
      inventory: new InMemoryInventoryRepository(initialProducts),
      orders: new InMemoryOrderRepository(),
    };
  }

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
  return new InventoryManagement([], {
    products: productRepository,
    inventory: inventoryRepository,
    orders: orderRepository,
  });
}
