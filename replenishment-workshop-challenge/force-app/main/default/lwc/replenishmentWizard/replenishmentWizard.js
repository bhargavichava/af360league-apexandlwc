import { LightningElement, api } from 'lwc';
import createReplenishmentState from 'c/replenishmentStateManager';

const STEP_LABELS = ['Store & Date', 'Choose Products', 'Review & Create'];

export default class ReplenishmentWizard extends LightningElement {
  @api botId;
  // TODO FOR THE CHALLENGE (Task 1):
  // Add () to invoke the state-manager factory.
  replenishmentState = createReplenishmentState();
  currentStep = 1;
  stepOneValid = false;
  isComplete = false;
  _recordId;

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    if (value === this._recordId) {
      return;
    }
    this._recordId = value;
    this.replenishmentState.value.reset({ storeId: value || null });
    this.currentStep = 1;
    this.stepOneValid = false;
    this.isComplete = false;
  }

  get steps() {
    return STEP_LABELS.map((label, index) => {
      const number = index + 1;
      let cssClass = 'step';
      if (number === this.currentStep) {
        cssClass += ' step_active';
      } else if (number < this.currentStep || this.isComplete) {
        cssClass += ' step_complete';
      }
      return {
        number,
        label,
        cssClass,
        ariaCurrent: number === this.currentStep ? 'step' : undefined
      };
    });
  }

  get isStepOne() {
    return this.currentStep === 1;
  }

  get isStepTwo() {
    return this.currentStep === 2;
  }

  get isStepThree() {
    return this.currentStep === 3;
  }

  get showBack() {
    return this.currentStep > 1 && !this.isComplete;
  }

  get showNext() {
    return this.currentStep < 3 && !this.isComplete;
  }

  get showFooter() {
    return this.showBack || this.showNext;
  }

  get nextDisabled() {
    if (this.currentStep === 1) {
      return !this.stepOneValid;
    }
    if (this.currentStep === 2) {
      return this.replenishmentState.value.productCount === 0;
    }
    return true;
  }

  handleStepOneValidity(event) {
    this.stepOneValid = event.detail.valid;
  }

  handleBack() {
    this.currentStep = Math.max(1, this.currentStep - 1);
  }

  handleNext() {
    if (!this.nextDisabled) {
      this.currentStep = Math.min(3, this.currentStep + 1);
    }
  }

  handleOrderCreated() {
    this.isComplete = true;
  }

  @api
  reset() {
    this.replenishmentState.value.reset({
      storeId: this._recordId || null
    });
    this.currentStep = 1;
    this.stepOneValid = false;
    this.isComplete = false;
  }
}
