export interface Product { productId: string; name: string }
export interface InitialProduct extends Product { availableQuantity: number }
export interface Order { orderId: string; status: "created" | "confirmed"; lines: { productId: string; quantity: number }[] }

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
  private readonly products: Product[];
  public constructor(initialProducts: readonly Product[]) { this.products = initialProducts.map(product => ({ ...product })); }
  public findById(productId: string): Product | undefined { return this.products.find(product => product.productId === productId); }
  public list(): Product[] { return this.products.map(product => ({ ...product })); }
}
export class InMemoryInventoryRepository implements InventoryRepository {
  private readonly quantities = new Map<string, number>();
  public constructor(initialProducts: readonly InitialProduct[]) { for (const product of initialProducts) this.quantities.set(product.productId, product.availableQuantity); }
  public getAvailableQuantity(productId: string): number | undefined { return this.quantities.get(productId); }
  public setAvailableQuantity(productId: string, availableQuantity: number): void { this.quantities.set(productId, availableQuantity); }
}
export class InMemoryOrderRepository implements OrderRepository {
  private readonly orders = new Map<string, Order>();
  public findById(orderId: string): Order | undefined { return this.orders.get(orderId); }
  public list(): Order[] { return [...this.orders.values()]; }
  public save(order: Order): void { this.orders.set(order.orderId, order); }
}

export class InventoryManagement {
  private readonly productRepository: ProductRepository;
  private readonly inventoryRepository: InventoryRepository;
  private readonly orderRepository: OrderRepository;
  private readonly auditTrail: string[] = [];

  public constructor(initialProducts: readonly InitialProduct[]);
  public constructor(productRepository: ProductRepository, inventoryRepository: InventoryRepository, orderRepository: OrderRepository);
  public constructor(first: readonly InitialProduct[] | ProductRepository, inventoryRepository?: InventoryRepository, orderRepository?: OrderRepository) {
    if (Array.isArray(first)) {
      this.productRepository = new InMemoryProductRepository(first);
      this.inventoryRepository = new InMemoryInventoryRepository(first);
      this.orderRepository = new InMemoryOrderRepository();
    } else {
      this.productRepository = first as ProductRepository;
      this.inventoryRepository = inventoryRepository!;
      this.orderRepository = orderRepository!;
    }
  }

  public listProducts(): Product[] { return this.productRepository.list(); }
  public findProduct(productId: string): Product | undefined { return this.productRepository.findById(productId); }
  public getAvailableQuantity(productId: string): number | undefined { return this.inventoryRepository.getAvailableQuantity(productId); }
  public replaceQuantity(productId: string, quantity: number): void { this.inventoryRepository.setAvailableQuantity(productId, quantity); }
  public getOrder(orderId: string): Order | undefined { return this.orderRepository.findById(orderId); }
  public listOrders(): Order[] { return this.orderRepository.list(); }
  public saveOrder(order: Order): void { this.orderRepository.save(order); this.auditTrail.push(order.orderId); }
  public getAuditTrail(): string[] { return [...this.auditTrail]; }
}

export function createInventoryManagementWithRepositories(
  productRepository: ProductRepository,
  inventoryRepository: InventoryRepository,
  orderRepository: OrderRepository,
): InventoryManagement {
  return new InventoryManagement(productRepository, inventoryRepository, orderRepository);
}
