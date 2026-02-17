namespace OrderSystem;

public interface INotificationService
{
    Task SendConfirmationAsync(string customerEmail, string orderId, CancellationToken ct = default);
}
