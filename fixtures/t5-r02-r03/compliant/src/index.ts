export interface Product { productId: string; name: string }
export interface InitialProduct extends Product { availableQuantity: number }
export interface OrderLine { productId: string; quantity: number }
export interface Order { orderId: string; status: "draft" | "confirmed"; lines: OrderLine[] }
export interface ProductRepository { findById(productId: string): Product | undefined; list(): Product[] }
export interface InventoryRepository { getAvailableQuantity(productId: string): number | undefined; setAvailableQuantity(productId: string, availableQuantity: number): void }
export interface OrderRepository { findById(orderId: string): Order | undefined; list(): Order[]; save(order: Order): void }
export class InventoryManagementError extends Error { public constructor(public readonly code: string) { super(code); } }
const copyOrder = (order: Order): Order => ({ ...order, lines: order.lines.map(line => ({ ...line })) });

export class InMemoryProductRepository implements ProductRepository {
  private readonly products: Product[];
  public constructor(products: readonly Product[]) { this.products = products.map(product => ({ ...product })); }
  public findById(id: string): Product | undefined { const value = this.products.find(product => product.productId === id); return value && { ...value }; }
  public list(): Product[] { return this.products.map(product => ({ ...product })); }
}
export class InMemoryInventoryRepository implements InventoryRepository {
  private readonly quantities: Map<string, number>;
  public constructor(products: readonly InitialProduct[]) { this.quantities = new Map(products.map(product => [product.productId, product.availableQuantity])); }
  public getAvailableQuantity(id: string): number | undefined { return this.quantities.get(id); }
  public setAvailableQuantity(id: string, quantity: number): void { this.quantities.set(id, quantity); }
}
export class InMemoryOrderRepository implements OrderRepository {
  private readonly orders = new Map<string, Order>();
  public findById(id: string): Order | undefined { const value = this.orders.get(id); return value && copyOrder(value); }
  public list(): Order[] { return [...this.orders.values()].map(copyOrder); }
  public save(order: Order): void { this.orders.set(order.orderId, copyOrder(order)); }
}

export class InventoryManagement {
  private readonly productRepository: ProductRepository;
  private readonly inventoryRepository: InventoryRepository;
  private readonly orderRepository: OrderRepository;
  private nextOrderNumber = 1;
  public constructor(products: readonly InitialProduct[]);
  public constructor(products: ProductRepository, inventory: InventoryRepository, orders: OrderRepository);
  public constructor(first: readonly InitialProduct[] | ProductRepository, inventory?: InventoryRepository, orders?: OrderRepository) {
    if (Array.isArray(first)) {
      this.productRepository = new InMemoryProductRepository(first);
      this.inventoryRepository = new InMemoryInventoryRepository(first);
      this.orderRepository = new InMemoryOrderRepository();
    } else {
      this.productRepository = first as ProductRepository;
      this.inventoryRepository = inventory!;
      this.orderRepository = orders!;
    }
  }
  public listProducts(): Product[] { return this.productRepository.list().sort((a, b) => a.productId.localeCompare(b.productId)); }
  public getAvailableQuantity(id: string): number { const value = this.inventoryRepository.getAvailableQuantity(id); if (value === undefined) throw new InventoryManagementError("PRODUCT_NOT_FOUND"); return value; }
  public createOrder(lines: OrderLine[]): Order {
    for (const line of lines) if (this.productRepository.findById(line.productId) === undefined) throw new InventoryManagementError("PRODUCT_NOT_FOUND");
    const order: Order = { orderId: `O-${String(this.nextOrderNumber++).padStart(3, "0")}`, status: "draft", lines: lines.map(line => ({ ...line })) };
    this.orderRepository.save(order); return copyOrder(order);
  }
  public confirmOrder(id: string): Order {
    const order = this.orderRepository.findById(id); if (order === undefined) throw new InventoryManagementError("ORDER_NOT_FOUND");
    for (const line of order.lines) if (this.getAvailableQuantity(line.productId) < line.quantity) throw new InventoryManagementError("INSUFFICIENT_STOCK");
    for (const line of order.lines) this.inventoryRepository.setAvailableQuantity(line.productId, this.getAvailableQuantity(line.productId) - line.quantity);
    const confirmed: Order = { ...order, status: "confirmed" }; this.orderRepository.save(confirmed); return copyOrder(confirmed);
  }
  public getOrder(id: string): Order { const order = this.orderRepository.findById(id); if (order === undefined) throw new InventoryManagementError("ORDER_NOT_FOUND"); return order; }
  public listOrders(): Order[] { return this.orderRepository.list().sort((a, b) => a.orderId.localeCompare(b.orderId)); }
}
export function createInventoryManagementWithRepositories(products: ProductRepository, inventory: InventoryRepository, orders: OrderRepository): InventoryManagement { return new InventoryManagement(products, inventory, orders); }
