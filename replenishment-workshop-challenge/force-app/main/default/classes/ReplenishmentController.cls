/**
 * UI facade for store replenishment. All reads and writes explicitly execute in
 * user mode so object permissions, field access, and record sharing are enforced.
 */
public inherited sharing class ReplenishmentController {
    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Decimal MAX_ORDER_QUANTITY = 1000000;

    public class StoreInfoDTO {
        @AuraEnabled public Id storeId { get; set; }
        @AuraEnabled public String storeName { get; set; }
        @AuraEnabled public String storeType { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
    }

    public class ProductRecommendationDTO {
        @AuraEnabled public Id storeProductId { get; set; }
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String sku { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public Decimal currentStock { get; set; }
        @AuraEnabled public Decimal safetyStock { get; set; }
        @AuraEnabled public Decimal averageDailySales { get; set; }
        @AuraEnabled public Decimal leadTimeDays { get; set; }
        @AuraEnabled public Decimal defaultOrderQuantity { get; set; }
        @AuraEnabled public Decimal recommendedQuantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public String formulaName { get; set; }
        @AuraEnabled public String explanation { get; set; }
    }

    public class ProductPageDTO {
        @AuraEnabled public List<ProductRecommendationDTO> products { get; set; }
        @AuraEnabled public Integer startIndex { get; set; }
        @AuraEnabled public Integer nextIndex { get; set; }
        @AuraEnabled public Integer pageSize { get; set; }
        @AuraEnabled public Integer totalRecords { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }

        public ProductPageDTO() {
            products = new List<ProductRecommendationDTO>();
        }
    }

    public class OrderSelectionDTO {
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
    }

    public class CreateOrderRequestDTO {
        @AuraEnabled public Id storeId { get; set; }
        @AuraEnabled public Date requestedDate { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public List<OrderSelectionDTO> selections { get; set; }
    }

    public class CreateOrderResultDTO {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public Id orderId { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public Integer lineCount { get; set; }
        @AuraEnabled public Decimal totalQuantity { get; set; }
        @AuraEnabled public String message { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static StoreInfoDTO getStoreInfo(Id storeId) {
        requireId(storeId, 'Select a retail store.');
        List<RetailStore> stores = [
            SELECT Id, Name, StoreType, AccountId, Account.Name
            FROM RetailStore
            WHERE Id = :storeId
            WITH USER_MODE
            LIMIT 1
        ];
        if (stores.isEmpty()) {
            throw new AuraHandledException('The retail store was not found or is not accessible.');
        }

        RetailStore store = stores[0];
        StoreInfoDTO dto = new StoreInfoDTO();
        dto.storeId = store.Id;
        dto.storeName = store.Name;
        dto.storeType = store.StoreType;
        dto.accountId = store.AccountId;
        dto.accountName = store.Account == null ? null : store.Account.Name;
        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static ProductPageDTO getEligibleProducts(
        Id storeId,
        Integer startIndex,
        Integer pageSize
    ) {
        return getEligibleProductsInternal(storeId, null, startIndex, pageSize);
    }

    @AuraEnabled(cacheable=true)
    public static ProductPageDTO getEligibleProductsPage(
        Id storeId,
        String searchTerm,
        Integer startIndex,
        Integer pageSize
    ) {
        return getEligibleProductsInternal(storeId, searchTerm, startIndex, pageSize);
    }

    private static ProductPageDTO getEligibleProductsInternal(
        Id storeId,
        String searchTerm,
        Integer startIndex,
        Integer pageSize
    ) {
        requireId(storeId, 'Select a retail store.');
        Integer safeStart = startIndex == null ? 0 : startIndex;
        Integer safeSize = pageSize == null ? DEFAULT_PAGE_SIZE : pageSize;
        if (safeStart < 0) {
            throw new AuraHandledException('The page start index cannot be negative.');
        }
        if (safeSize < 1 || safeSize > MAX_PAGE_SIZE) {
            throw new AuraHandledException('Page size must be between 1 and ' + MAX_PAGE_SIZE + '.');
        }

        StoreInfoDTO store = getStoreInfo(storeId);
        Set<Id> assortmentIds = getActiveAssortmentIds(storeId);
        ProductPageDTO response = new ProductPageDTO();
        response.startIndex = safeStart;
        response.nextIndex = safeStart;
        response.pageSize = safeSize;
        response.totalRecords = 0;
        response.hasMore = false;
        if (assortmentIds.isEmpty()) {
            return response;
        }

        String queryText =
            'SELECT Id, ProductId, Product.Name, Product.ProductCode, Product.StockKeepingUnit, Product.DisplayUrl, ' +
            'Current_Stock__c, Safety_Stock__c, Average_Daily_Sales__c, Lead_Time_Days__c ' +
            'FROM StoreProduct ' +
            'WHERE RetailStoreId = :storeId ' +
            'AND Product.IsActive = true ' +
            'AND StartDate <= :asOfDate ' +
            'AND (EndDate = null OR EndDate >= :asOfDate) ' +
            'AND ProductId IN (SELECT ProductId FROM AssortmentProduct WHERE AssortmentId IN :assortmentIds) ' +
            'AND (Product.Name LIKE :searchPattern OR Product.ProductCode LIKE :searchPattern) ' +
            'ORDER BY Product.Name, Id';
        String searchPattern = '%' + (String.isBlank(searchTerm) ? '' : searchTerm.trim()) + '%';
        Map<String, Object> binds = new Map<String, Object>{
            'storeId' => storeId,
            'assortmentIds' => assortmentIds,
            'asOfDate' => Date.today(),
            'searchPattern' => searchPattern
        };
        // TODO FOR THE CHALLENGE (Task 2):
        // Replace null with queryText.
        Database.PaginationCursor cursor =
            Database.getPaginationCursorWithBinds(
    queryText,
    binds,
    AccessLevel.USER_MODE
);
        Integer totalRecords = cursor.getNumRecords();
        response.totalRecords = totalRecords;
        if (safeStart >= totalRecords) {
            response.nextIndex = totalRecords;
            return response;
        }

        // TODO FOR THE CHALLENGE (Task 2):
        // Replace 0 with totalRecords - safeStart.
        Integer countToFetch = Math.min(safeSize, totalRecords - safeStart);
        Database.CursorFetchResult fetched = cursor.fetchPage(safeStart, countToFetch);
        List<StoreProduct> storeProducts = new List<StoreProduct>();
        Set<Id> productIds = new Set<Id>();
        for (SObject record : fetched.getRecords()) {
            StoreProduct storeProduct = (StoreProduct) record;
            storeProducts.add(storeProduct);
            productIds.add(storeProduct.ProductId);
        }
        Map<Id, Decimal> defaultQuantities =
            getDefaultOrderQuantities(assortmentIds, productIds);
        Map<Id, Decimal> prices = getStandardPrices(productIds);

        for (StoreProduct storeProduct : storeProducts) {
            Decimal defaultQuantity = defaultQuantities.get(storeProduct.ProductId);
            ReplenishmentFormulaService.FormulaResult formula =
                ReplenishmentFormulaService.calculate(storeProduct, store.storeType, defaultQuantity);
            ProductRecommendationDTO dto = new ProductRecommendationDTO();
            dto.storeProductId = storeProduct.Id;
            dto.productId = storeProduct.ProductId;
            dto.productName = storeProduct.Product == null ? null : storeProduct.Product.Name;
            dto.sku = storeProduct.Product == null
                ? null
                : (String.isBlank(storeProduct.Product.StockKeepingUnit)
                    ? storeProduct.Product.ProductCode
                    : storeProduct.Product.StockKeepingUnit);
            dto.imageUrl = storeProduct.Product == null ||
                String.isBlank(storeProduct.Product.DisplayUrl)
                ? null
                : storeProduct.Product.DisplayUrl;
            dto.currentStock = zeroIfNull(storeProduct.Current_Stock__c);
            dto.safetyStock = zeroIfNull(storeProduct.Safety_Stock__c);
            dto.averageDailySales = zeroIfNull(storeProduct.Average_Daily_Sales__c);
            dto.leadTimeDays = zeroIfNull(storeProduct.Lead_Time_Days__c);
            dto.defaultOrderQuantity = zeroIfNull(defaultQuantity);
            dto.recommendedQuantity = formula.quantity;
            dto.unitPrice = zeroIfNull(prices.get(storeProduct.ProductId));
            dto.formulaName = formula.formulaName;
            dto.explanation = formula.explanation;
            response.products.add(dto);
        }

        // TODO FOR THE CHALLENGE (Task 2):
        // Replace 0 and false with the correct expressions.
       response.nextIndex = safeStart + countToFetch;
       response.hasMore = response.nextIndex < totalRecords;
        return response;
    }

    @AuraEnabled
    public static CreateOrderResultDTO createReplenishmentOrder(CreateOrderRequestDTO request) {
        if (request == null) {
            throw new AuraHandledException('Order details are required.');
        }
        requireId(request.storeId, 'Select a retail store.');
        Date effectiveDate = request.requestedDate == null
            ? Date.today()
            : request.requestedDate;
        if (effectiveDate < Date.today()) {
            throw new AuraHandledException('The requested order date cannot be in the past.');
        }
        String notes = String.isBlank(request.notes) ? null : request.notes.trim();
        if (notes != null && notes.length() > 1000) {
            throw new AuraHandledException('Order notes cannot exceed 1,000 characters.');
        }
        Map<Id, Decimal> quantities = validateAndAggregateSelections(request.selections);

        List<RetailStore> stores = [
            SELECT Id, AccountId
            FROM RetailStore
            WHERE Id = :request.storeId
            WITH USER_MODE
            LIMIT 1
        ];
        if (stores.isEmpty()) {
            throw new AuraHandledException('The retail store was not found or is not accessible.');
        }
        if (stores[0].AccountId == null) {
            throw new AuraHandledException('The retail store must be related to an account before ordering.');
        }

        Set<Id> assortmentIds = getActiveAssortmentIds(request.storeId);
        if (assortmentIds.isEmpty()) {
            throw new AuraHandledException('This store has no active assortment.');
        }
        Set<Id> selectedProductIds = quantities.keySet();
        Set<Id> eligibleProductIds = new Set<Id>();
        for (StoreProduct item : [
            SELECT ProductId
            FROM StoreProduct
            WHERE RetailStoreId = :request.storeId
                AND ProductId IN :selectedProductIds
                AND Product.IsActive = true
                AND StartDate <= TODAY
                AND (EndDate = NULL OR EndDate >= TODAY)
                AND ProductId IN (
                    SELECT ProductId
                    FROM AssortmentProduct
                    WHERE AssortmentId IN :assortmentIds
                )
            WITH USER_MODE
        ]) {
            eligibleProductIds.add(item.ProductId);
        }
        if (!eligibleProductIds.containsAll(selectedProductIds)) {
            throw new AuraHandledException(
                'One or more selected products are not in the store\'s active assortment.'
            );
        }

        Map<Id, PricebookEntry> entriesByProduct = new Map<Id, PricebookEntry>();
        for (PricebookEntry entry : [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :selectedProductIds
                AND Pricebook2.IsStandard = true
                AND Pricebook2.IsActive = true
                AND IsActive = true
            WITH USER_MODE
        ]) {
            entriesByProduct.put(entry.Product2Id, entry);
        }
        if (!entriesByProduct.keySet().containsAll(selectedProductIds)) {
            throw new AuraHandledException(
                'Every selected product needs an active standard price book entry.'
            );
        }

        PricebookEntry firstEntry = entriesByProduct.values()[0];
        Order orderRecord = new Order(
            AccountId = stores[0].AccountId,
            Retail_Store__c = request.storeId,
            Pricebook2Id = firstEntry.Pricebook2Id,
            EffectiveDate = effectiveDate,
            Description = notes,
            Status = 'Draft'
        );
        Savepoint savepoint = Database.setSavepoint();
        List<Database.SaveResult> orderResults = Database.insert(
            new List<Order>{ orderRecord },
            AccessLevel.USER_MODE
        );
        if (!orderResults[0].isSuccess()) {
            Database.rollback(savepoint);
            throw userModeDmlError('The replenishment order could not be created.', orderResults[0]);
        }

        List<OrderItem> orderItems = new List<OrderItem>();
        Decimal totalQuantity = 0;
        for (Id productId : quantities.keySet()) {
            PricebookEntry entry = entriesByProduct.get(productId);
            Decimal quantity = quantities.get(productId);
            orderItems.add(new OrderItem(
                OrderId = orderRecord.Id,
                PricebookEntryId = entry.Id,
                Quantity = quantity,
                UnitPrice = entry.UnitPrice
            ));
            totalQuantity += quantity;
        }
        List<Database.SaveResult> itemResults =
            Database.insert(orderItems, AccessLevel.USER_MODE);
        for (Database.SaveResult itemResult : itemResults) {
            if (!itemResult.isSuccess()) {
                Database.rollback(savepoint);
                throw userModeDmlError(
                    'The order was not saved because an order line could not be created.',
                    itemResult
                );
            }
        }

        Order createdOrder = [
            SELECT Id, OrderNumber
            FROM Order
            WHERE Id = :orderRecord.Id
            WITH USER_MODE
        ];
        CreateOrderResultDTO response = new CreateOrderResultDTO();
        response.success = true;
        response.orderId = createdOrder.Id;
        response.orderNumber = createdOrder.OrderNumber;
        response.lineCount = orderItems.size();
        response.totalQuantity = totalQuantity;
        response.message = 'Replenishment order ' + createdOrder.OrderNumber + ' was created.';
        return response;
    }

    private static Set<Id> getActiveAssortmentIds(Id storeId) {
        Set<Id> ids = new Set<Id>();
        Date today = Date.today();
        RetailStore store = [
            SELECT AccountId
            FROM RetailStore
            WHERE Id = :storeId
            WITH USER_MODE
        ];
        List<StoreAssortment> assignments;
        if (store.AccountId == null) {
            assignments = [
                SELECT AssortmentId
                FROM StoreAssortment
                WHERE RetailStoreId = :storeId
                    AND StartDate <= :today
                    AND (EndDate = NULL OR EndDate >= :today)
                WITH USER_MODE
            ];
        } else {
            assignments = [
                SELECT AssortmentId
                FROM StoreAssortment
                WHERE (RetailStoreId = :storeId OR AccountId = :store.AccountId)
                    AND StartDate <= :today
                    AND (EndDate = NULL OR EndDate >= :today)
                WITH USER_MODE
            ];
        }
        for (StoreAssortment assignment : assignments) {
            ids.add(assignment.AssortmentId);
        }
        return ids;
    }

    private static Map<Id, Decimal> getDefaultOrderQuantities(
        Set<Id> assortmentIds,
        Set<Id> productIds
    ) {
        Map<Id, Decimal> quantities = new Map<Id, Decimal>();
        if (productIds.isEmpty()) {
            return quantities;
        }
        for (AssortmentProduct item : [
            SELECT ProductId, DefaultOrderQuantity
            FROM AssortmentProduct
            WHERE AssortmentId IN :assortmentIds AND ProductId IN :productIds
            WITH USER_MODE
        ]) {
            Decimal candidate = zeroIfNull(item.DefaultOrderQuantity);
            Decimal existing = quantities.get(item.ProductId);
            if (existing == null || candidate > existing) {
                quantities.put(item.ProductId, candidate);
            }
        }
        return quantities;
    }

    private static Map<Id, Decimal> getStandardPrices(Set<Id> productIds) {
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
                AND Pricebook2.IsStandard = true
                AND Pricebook2.IsActive = true
                AND IsActive = true
            WITH USER_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    private static Map<Id, Decimal> validateAndAggregateSelections(
        List<OrderSelectionDTO> selections
    ) {
        if (selections == null || selections.isEmpty()) {
            throw new AuraHandledException('Select at least one product to order.');
        }
        Map<Id, Decimal> quantities = new Map<Id, Decimal>();
        for (OrderSelectionDTO selection : selections) {
            if (selection == null || selection.productId == null) {
                throw new AuraHandledException('Every order line must identify a product.');
            }
            if (selection.quantity == null || selection.quantity <= 0 ||
                selection.quantity > MAX_ORDER_QUANTITY ||
                selection.quantity.scale() > 2) {
                throw new AuraHandledException(
                    'Each quantity must be positive, no greater than ' +
                    MAX_ORDER_QUANTITY + ', and use at most two decimal places.'
                );
            }
            Decimal existing = quantities.get(selection.productId);
            Decimal combined = (existing == null ? 0 : existing) + selection.quantity;
            if (combined > MAX_ORDER_QUANTITY) {
                throw new AuraHandledException(
                    'The combined quantity for a product cannot exceed ' + MAX_ORDER_QUANTITY + '.'
                );
            }
            quantities.put(selection.productId, combined);
        }
        return quantities;
    }

    private static AuraHandledException userModeDmlError(
        String prefix,
        Database.SaveResult result
    ) {
        String detail = result.getErrors().isEmpty()
            ? ''
            : ' ' + result.getErrors()[0].getMessage();
        return new AuraHandledException(prefix + detail);
    }

    private static void requireId(Id value, String message) {
        if (value == null) {
            throw new AuraHandledException(message);
        }
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }
}
