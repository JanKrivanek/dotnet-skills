namespace OrderSystem;

public interface IOrderRepository
{
    Task SaveOrderAsync(Order order, CancellationToken ct = default);
}
