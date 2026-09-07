/**
 * Evaluates administrator-maintained replenishment policies through FormulaEval.
 * The context type and every formula-visible property are global as required by
 * FormulaEval when an Apex class is used as the evaluation context.
 */
global inherited sharing class ReplenishmentFormulaService {
    private static final String DEFAULT_EXPRESSION =
        'ROUND(MAX(SafetyStock + (AverageDailySales * LeadTimeDays) - CurrentStock, 0), 0)';

    global class FormulaContext {
        global Decimal CurrentStock { get; set; }
        global Decimal SafetyStock { get; set; }
        global Decimal AverageDailySales { get; set; }
        global Decimal LeadTimeDays { get; set; }
        global Decimal DefaultOrderQuantity { get; set; }

        global FormulaContext() {
        }
    }

    public class FormulaServiceException extends Exception {
    }

    public class FormulaResult {
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String formulaName { get; set; }
        @AuraEnabled public String explanation { get; set; }
    }

    public static FormulaResult calculate(
        StoreProduct storeProduct,
        String storeType,
        Decimal defaultOrderQuantity
    ) {
        if (storeProduct == null) {
            throw new FormulaServiceException('A store product is required to calculate replenishment.');
        }

        FormulaContext context = new FormulaContext();
        context.CurrentStock = valueOrZero(storeProduct.Current_Stock__c);
        context.SafetyStock = valueOrZero(storeProduct.Safety_Stock__c);
        context.AverageDailySales = valueOrZero(storeProduct.Average_Daily_Sales__c);
        context.LeadTimeDays = valueOrZero(storeProduct.Lead_Time_Days__c);
        context.DefaultOrderQuantity = valueOrZero(defaultOrderQuantity);
        validateContext(context);

        Replenishment_Formula__mdt policy = findPolicy(storeType);
        String expression = policy == null || String.isBlank(policy.Formula__c)
            ? DEFAULT_EXPRESSION
            : policy.Formula__c;

        FormulaResult result = new FormulaResult();
        result.quantity = evaluateExpression(expression, context);
        result.formulaName = policy == null ? 'Built-in Default' : policy.MasterLabel;
        result.explanation = policy == null
            ? 'Fallback policy: lead-time demand plus safety stock, less current stock.'
            : policy.Description__c;
        return result;
    }

    @TestVisible
    private static Decimal evaluateExpression(String expression, FormulaContext context) {
        try {
            // TODO FOR THE CHALLENGE (Task 3):
            // Replace null with a Formula.builder() chain that uses
            // FormulaContext, DECIMAL, and the supplied expression.
           FormulaEval.FormulaInstance formula = Formula.builder().withType(FormulaContext.class)
        .withReturnType(FormulaEval.FormulaReturnType.DECIMAL)
        .withFormula(expression)
        .build();
            Object rawValue = formula.evaluate(context);
            Decimal quantity = rawValue == null ? 0 : (Decimal) rawValue;
            return quantity < 0 ? 0 : quantity.setScale(0);
        } catch (Exception ex) {
            throw new FormulaServiceException(
                'The replenishment formula could not be evaluated. Ask an administrator to verify the active formula.'
            );
        }
    }

    private static Replenishment_Formula__mdt findPolicy(String storeType) {
        String normalizedType = normalize(storeType);
        Replenishment_Formula__mdt fallback;
        for (Replenishment_Formula__mdt policy : [
            SELECT DeveloperName, MasterLabel, Store_Type__c, Formula__c, Description__c
            FROM Replenishment_Formula__mdt
            WHERE Is_Active__c = true
            WITH USER_MODE
        ]) {
            if (policy.DeveloperName == 'Default' || normalize(policy.Store_Type__c) == 'default') {
                fallback = policy;
            }
            if (String.isNotBlank(normalizedType) &&
                normalize(policy.Store_Type__c) == normalizedType) {
                return policy;
            }
        }
        return fallback;
    }

    private static void validateContext(FormulaContext context) {
        if (context.CurrentStock < 0 || context.SafetyStock < 0 ||
            context.AverageDailySales < 0 || context.LeadTimeDays < 0 ||
            context.DefaultOrderQuantity < 0) {
            throw new FormulaServiceException(
                'Stock, sales, lead time, and default order quantities cannot be negative.'
            );
        }
    }

    private static Decimal valueOrZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static String normalize(String value) {
        return String.isBlank(value)
            ? ''
            : value.toLowerCase().replace(' ', '').replace('_', '').replace('-', '');
    }
}
