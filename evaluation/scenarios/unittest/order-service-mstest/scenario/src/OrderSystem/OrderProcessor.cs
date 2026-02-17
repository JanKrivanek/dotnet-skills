namespace OrderSystem;

public class OrderProcessor
{
    private readonly IOrderRepository _repository;
    private readonly INotificationService _notifications;

    public OrderProcessor(IOrderRepository repository, INotificationService notifications)
    {
        _repository = repository ?? throw new ArgumentNullException(nameof(repository));
        _notifications = notifications ?? throw new ArgumentNullException(nameof(notifications));
    }

    public async Task<OrderResult> ProcessOrderAsync(Order order, CancellationToken ct = default)
    {
        if (order is null) throw new ArgumentNullException(nameof(order));
        if (order.Items.Count == 0) throw new ArgumentException("Order must have at least one item.", nameof(order));
        if (order.Items.Any(i => i.Quantity <= 0))
            throw new ArgumentException("All items must have positive quantity.", nameof(order));

        var total = order.Items.Sum(i => i.UnitPrice * i.Quantity);
        if (total > 10000m)
            return new OrderResult(false, "Order exceeds maximum allowed total.");

        await _repository.SaveOrderAsync(order, ct);
        await _notifications.SendConfirmationAsync(order.CustomerEmail, order.Id, ct);

        return new OrderResult(true, $"Order {order.Id} processed successfully. Total: {total:C}");
    }
}

public record Order(string Id, string CustomerEmail, List<OrderItem> Items);
public record OrderItem(string ProductId, int Quantity, decimal UnitPrice);
public record OrderResult(bool Success, string Message);
