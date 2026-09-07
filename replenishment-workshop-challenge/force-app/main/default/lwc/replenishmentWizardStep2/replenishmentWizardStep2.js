import { LightningElement } from 'lwc';
// eslint-disable-next-line no-unused-vars -- used when Task 1 is completed
import { fromContext } from '@lwc/state';
import getEligibleProductsPage from '@salesforce/apex/ReplenishmentController.getEligibleProductsPage';
// eslint-disable-next-line no-unused-vars -- used when Task 1 is completed
import createReplenishmentState from 'c/replenishmentStateManager';

const PAGE_SIZE = 2;
const SEARCH_DELAY = 350;

export default class ReplenishmentWizardStep2 extends LightningElement {
  // TODO FOR THE CHALLENGE (Task 1):
  // Replace undefined with fromContext(createReplenishmentState).
  replenishmentState = fromContext(createReplenishmentState);
  products = [];
  searchTerm = '';
  currentStartIndex = 0;
  nextStartIndex = null;
  pageHistory = [];
  isLoading = false;
  errorMessage;
  searchTimer;
  requestSequence = 0;

  connectedCallback() {
    this.loadProducts();
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
    this.requestSequence += 1;
  }

  get hasProducts() {
    return this.products.length > 0;
  }

  get hasPrevious() {
    return this.pageHistory.length > 0;
  }

  get hasNext() {
    return this.nextStartIndex !== null;
  }

  get previousDisabled() {
    return this.isLoading || !this.hasPrevious;
  }

  get nextDisabled() {
    return this.isLoading || !this.hasNext;
  }

  get selectedSummary() {
    const count = this.replenishmentState.value.productCount;
    const units = this.replenishmentState.value.totalUnits;
    return `${count} products selected · ${units} total units`;
  }

  async loadProducts() {
    const requestId = ++this.requestSequence;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const result = await getEligibleProductsPage({
        storeId: this.replenishmentState.value.storeId,
        searchTerm: this.searchTerm,
        startIndex: this.currentStartIndex,
        pageSize: PAGE_SIZE
      });
      if (requestId !== this.requestSequence) {
        return;
      }
      const rawProducts =
        result?.products || result?.items || result?.records || [];
      const selectedById = new Map(
        this.replenishmentState.value.chosenProducts.map((product) => [
          product.productId,
          product
        ])
      );
      this.products = rawProducts
        .map((product) => this.normalizeProduct(product))
        .filter((product) => product.productId)
        .map((product) => {
          const selected = selectedById.get(product.productId);
          return {
            ...product,
            selected: Boolean(selected),
            quantity: selected?.quantity ?? product.defaultOrderQuantity
          };
        });
      this.nextStartIndex = result?.hasMore ? result.nextIndex : null;
    } catch (error) {
      if (requestId !== this.requestSequence) {
        return;
      }
      this.products = [];
      this.nextStartIndex = null;
      this.errorMessage = this.reduceError(error);
    } finally {
      if (requestId === this.requestSequence) {
        this.isLoading = false;
      }
    }
  }

  normalizeProduct(product) {
    const recommendedQuantity = Number(product.recommendedQuantity) || 0;
    const configuredDefault = Number(product.defaultOrderQuantity) || 1;
    return {
      productId: product.productId,
      name: product.productName || product.name || '',
      productCode: product.sku || product.productCode || '',
      imageUrl: product.imageUrl || '',
      currentStock: Number(product.currentStock) || 0,
      safetyStock: Number(product.safetyStock) || 0,
      recommendedQuantity,
      unitPrice: Number(product.unitPrice) || 0,
      defaultOrderQuantity:
        recommendedQuantity > 0
          ? recommendedQuantity
          : Math.max(1, configuredDefault)
    };
  }

  handleSearchInput(event) {
    this.searchTerm = event.target.value.trim();
    clearTimeout(this.searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => {
      this.currentStartIndex = 0;
      this.nextStartIndex = null;
      this.pageHistory = [];
      this.loadProducts();
    }, SEARCH_DELAY);
  }

  handleSelectionChange(event) {
    const { selected, product } = event.detail;
    if (selected) {
      this.replenishmentState.value.selectProduct(product);
    } else {
      this.replenishmentState.value.removeProduct(product.productId);
    }
    this.products = this.products.map((item) => (
      item.productId === product.productId ? { ...item, selected } : item
    ));
  }

  handleQuantityChange(event) {
    const { productId, quantity } = event.detail;
    this.replenishmentState.value.updateProductQuantity(productId, quantity);
    this.products = this.products.map((product) => (
      product.productId === productId ? { ...product, quantity } : product
    ));
  }

  handleNextPage() {
    if (this.nextStartIndex === null) {
      return;
    }
    this.pageHistory = [...this.pageHistory, this.currentStartIndex];
    this.currentStartIndex = this.nextStartIndex;
    this.loadProducts();
  }

  handlePreviousPage() {
    if (!this.pageHistory.length) {
      return;
    }
    const history = [...this.pageHistory];
    this.currentStartIndex = history.pop() ?? 0;
    this.pageHistory = history;
    this.loadProducts();
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      'Eligible products could not be loaded.'
    );
  }
}
