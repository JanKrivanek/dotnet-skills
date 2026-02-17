namespace Calculator;

public class MathService
{
    public int Add(int a, int b) => checked(a + b);

    public double Divide(double numerator, double denominator)
    {
        if (denominator == 0)
            throw new DivideByZeroException("Denominator cannot be zero.");
        return numerator / denominator;
    }

    public long Factorial(int n)
    {
        if (n < 0)
            throw new ArgumentOutOfRangeException(nameof(n), "Value must be non-negative.");
        if (n <= 1) return 1;
        return checked(n * Factorial(n - 1));
    }

    public bool IsPrime(int number)
    {
        if (number < 2) return false;
        if (number == 2) return true;
        if (number % 2 == 0) return false;
        for (int i = 3; i * i <= number; i += 2)
        {
            if (number % i == 0) return false;
        }
        return true;
    }
}
