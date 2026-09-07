import { LightningElement, api } from 'lwc';
// eslint-disable-next-line no-unused-vars -- used when Task 1 is completed
import { fromContext } from '@lwc/state';
import getStoreInfo from '@salesforce/apex/ReplenishmentController.getStoreInfo';
// eslint-disable-next-line no-unused-vars -- used when Task 1 is completed
import createReplenishmentState from 'c/replenishmentStateManager';

export default class ReplenishmentWizardStep1 extends LightningElement {
  _recordId;
  // TODO FOR THE CHALLENGE (Task 1):
  // Replace undefined with fromContext(createReplenishmentState).
  replenishmentState = fromContext(createReplenishmentState);
  isLoading = true;
  errorMessage;
  requestSequence = 0;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value === this._recordId) {
      return;
    }
    this._recordId = value;
    if (this.isConnected) {
      this.initialize();
    }
  }

  connectedCallback() {
    this.initialize();
  }

  async initialize() {
    const requestId = ++this.requestSequence;
    this.isLoading = true;
    this.errorMessage = undefined;
    const state = this.replenishmentState.value;
    if (!state.storeId && this.recordId) {
      state.setStore({ storeId: this.recordId });
    }
    if (!state.orderDate) {
      state.setOrderDate(this.today);
    }
    if (!state.storeId) {
      this.errorMessage = 'Open this assistant from a Retail Store record.';
      this.isLoading = false;
      this.notifyValidity();
      return;
    }

    try {
      const result = await getStoreInfo({ storeId: state.storeId });
      if (requestId !== this.requestSequence) {
        return;
      }
      const store = result?.store || result || {};
      state.setStore({
        storeId: store.storeId || store.Id || state.storeId,
        storeName: store.storeName || store.Name || '',
        storeType:
          store.storeType || store.StoreType || store.StoreType__c || ''
      });
    } catch (error) {
      if (requestId !== this.requestSequence) {
        return;
      }
      this.errorMessage = this.reduceError(error);
    } finally {
      if (requestId === this.requestSequence) {
        this.isLoading = false;
        this.notifyValidity();
      }
    }
  }

  get today() {
    const now = new Date();
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60 * 1000);
    return local.toISOString().slice(0, 10);
  }

  get storeName() {
    return this.replenishmentState.value.storeName || 'Retail Store';
  }

  get storeType() {
    return this.replenishmentState.value.storeType || 'Not specified';
  }

  get storeId() {
    return this.replenishmentState.value.storeId;
  }

  get orderDate() {
    return this.replenishmentState.value.orderDate;
  }

  get dateValid() {
    return Boolean(this.orderDate && this.orderDate >= this.today);
  }

  handleDateChange(event) {
    this.replenishmentState.value.setOrderDate(event.detail.value);
    event.target.reportValidity();
    this.notifyValidity();
  }

  notifyValidity() {
    this.dispatchEvent(
      new CustomEvent('stepvalidity', {
        detail: {
          valid: Boolean(
            !this.errorMessage &&
              this.replenishmentState.value.storeId &&
              this.dateValid
          )
        }
      })
    );
  }

  reduceError(error) {
    return (
      error?.body?.message ||
      error?.message ||
      'The retail store could not be loaded.'
    );
  }
}
