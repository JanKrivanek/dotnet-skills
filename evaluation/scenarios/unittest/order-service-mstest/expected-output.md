# Expected Findings: order-service-mstest Scenario

## Overview
This scenario evaluates the ability to generate comprehensive unit tests for an `OrderProcessor` class that has **injected dependencies** (`IOrderRepository`, `INotificationService`) using the MSTest framework. The test project references MSTest and Moq — the response must detect MSTest and use Moq for mocking (no hand-written fakes/stubs).

## Framework Detection
- **Must detect MSTest** from the `OrderSystem.Tests.csproj` package reference (`MSTest`)
- Must use MSTest-specific attributes and assertions — NOT xUnit or NUnit

## Expected Test Structure

### Attributes
- `[TestClass]` on the test class
- `[TestMethod]` on each test method
- `[TestInitialize]` for common mock/setup initialization
- `[DataRow]` for parameterized tests (if applicable)

### Assertions
- `Assert.AreEqual` for value comparisons
- `Assert.IsTrue` / `Assert.IsFalse` for boolean checks
- `Assert.ThrowsExceptionAsync<T>` for async exception testing
- `Assert.IsNotNull` where appropriate

### Naming Convention
- Method names should follow `MethodName_Condition_ExpectedOutcome` pattern
- Test class should be named `OrderProcessorTests`

## Expected Test Coverage

### Constructor tests
- Passing `null` for `repository` parameter should throw `ArgumentNullException`
- Passing `null` for `notifications` parameter should throw `ArgumentNullException`

### ProcessOrderAsync — Input Validation
- `null` order should throw `ArgumentNullException`
- Order with empty items list should throw `ArgumentException` with message about "at least one item"
- Order with an item having zero or negative quantity should throw `ArgumentException` about "positive quantity"

### ProcessOrderAsync — Business Rules
- Order total exceeding 10,000 should return `OrderResult(false, ...)` with message about exceeding maximum
  - **Important**: When total > 10,000, the repository and notification service should NOT be called (verify with Moq)
- Valid order should return `OrderResult(true, ...)` with success message containing the order ID and total

### ProcessOrderAsync — Dependency Interaction
- Valid order should call `_repository.SaveOrderAsync` exactly once with the correct order and cancellation token
- Valid order should call `_notifications.SendConfirmationAsync` exactly once with the correct email, order ID, and cancellation token
- Should verify the order of operations (save first, then notify) if possible

### ProcessOrderAsync — Cancellation
- CancellationToken should be propagated to both repository and notification service calls

## Mocking Requirements
- **Must use Moq** to mock `IOrderRepository` and `INotificationService`
- **Must NOT create** stub, fake, or dummy implementations of these interfaces
- Should use `Mock<T>` and `.Setup()` / `.Verify()` patterns
- Should use `It.IsAny<>()` or specific argument matchers as appropriate
- `[TestInitialize]` should create fresh mocks for each test

## Code Quality Requirements
- Arrange-Act-Assert (AAA) pattern in every test
- Async test methods should return `async Task` (not `void`)
- All necessary `using` directives present (including `Moq`, `OrderSystem`)
- Test file should compile without errors
- No hand-written fake/stub/dummy classes — exclusively Moq

## Key Concepts That Should Be Demonstrated
- MSTest framework detection from project references
- `[TestClass]`, `[TestMethod]`, `[TestInitialize]` usage
- Moq for dependency mocking (`Mock<T>`, `Setup`, `Verify`)
- Async test patterns (`async Task`, `Assert.ThrowsExceptionAsync<T>`)
- Verifying mock interactions (method called / not called)
- Constructor null-guard testing
- Business rule validation testing
- Clean test organization with descriptive method names
