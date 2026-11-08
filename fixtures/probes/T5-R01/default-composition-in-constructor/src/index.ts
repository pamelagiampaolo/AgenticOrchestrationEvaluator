// Sonda T5-R01 (forma realistica, attesa conforme): costruttore originale con initialProducts e
// overload con i repository; la composizione predefinita e' nel costruttore.
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

export class InventoryManagement {
  private readonly products: ProductRepository;
  private readonly inventory: InventoryRepository;
  private readonly orders: OrderRepository;

  public constructor(initialProducts: InitialProduct[]);
  public constructor(products: ProductRepository, inventory: InventoryRepository, orders: OrderRepository);
  public constructor(
    first: InitialProduct[] | ProductRepository,
    inventory?: InventoryRepository,
    orders?: OrderRepository,
  ) {
    if (Array.isArray(first)) {
      this.products = new InMemoryProductRepository(first);
      this.inventory = new InMemoryInventoryRepository(first);
      this.orders = new InMemoryOrderRepository();
    } else {
      if (inventory === undefined || orders === undefined) {
        throw new TypeError("All repositories are required.");
      }
      this.products = first;
      this.inventory = inventory;
      this.orders = orders;
    }
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
  return new InventoryManagement(productRepository, inventoryRepository, orderRepository);
}
