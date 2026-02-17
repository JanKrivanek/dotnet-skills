# Expected Findings: calculator-xunit Scenario

## Overview
This scenario evaluates the ability to generate comprehensive unit tests for a simple `MathService` class using the xUnit framework. The test project already references xUnit and Moq — the response should detect xUnit and produce well-structured tests.

## Framework Detection
- **Must detect xUnit** from the `Calculator.Tests.csproj` package references (`xunit`, `xunit.runner.visualstudio`)
- Must use xUnit-specific attributes and assertions — NOT MSTest or NUnit

## Expected Test Structure

### Attributes
- `[Fact]` for single-case tests
- `[Theory]` + `[InlineData]` for parameterized tests
- No `[TestClass]` or `[TestFixture]` (those are MSTest / NUnit)

### Assertions
- `Assert.Equal` for value comparisons
- `Assert.True` / `Assert.False` for boolean checks
- `Assert.Throws<T>` for synchronous exception testing

### Naming Convention
- Method names should follow `MethodName_Condition_ExpectedOutcome` pattern (or similar descriptive convention)
- Test class should be named `MathServiceTests`

## Expected Test Coverage

### Add method
- Normal addition (e.g. 2 + 3 = 5)
- Adding zero (identity)
- Negative numbers
- Overflow: `int.MaxValue + 1` should throw `OverflowException` (uses `checked` arithmetic)

### Divide method
- Normal division (e.g. 10 / 2 = 5)
- Division resulting in a decimal (e.g. 7 / 2 = 3.5)
- Divide by zero: should throw `DivideByZeroException` with message "Denominator cannot be zero."
- Edge cases: very large or very small numbers, negative divisor

### Factorial method
- Factorial(0) = 1
- Factorial(1) = 1
- Normal case (e.g. Factorial(5) = 120)
- Negative input: should throw `ArgumentOutOfRangeException`
- Large input causing overflow: should throw `OverflowException` (uses `checked` arithmetic)

### IsPrime method
- Numbers < 2 return false (0, 1, negative numbers)
- 2 is prime
- Small primes (3, 5, 7, 11, 13)
- Composite numbers (4, 6, 9, 15)
- Even numbers > 2 are not prime
- Larger primes (e.g. 97, 101)
- Should use `[Theory]` with `[InlineData]` for parameterized prime testing

## Code Quality Requirements
- Arrange-Act-Assert (AAA) pattern in every test
- No fake/stub/dummy classes created — mocking is not needed for this scenario since `MathService` has no dependencies, but no hand-written fakes should appear
- All necessary `using` directives present
- Test file should compile without errors
- Tests should be in the `Calculator.Tests` namespace (or similar)

## Key Concepts That Should Be Demonstrated
- xUnit framework detection from project references
- `[Fact]` vs `[Theory]`/`[InlineData]` usage
- `Assert.Throws<T>` for exception testing
- `checked` arithmetic overflow testing
- Parameterized testing for methods with many input variations
- Clean test organization with descriptive method names
