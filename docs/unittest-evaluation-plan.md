# Unittest Skills Evaluation Plan

## 1. Executive Summary

This plan extends the existing evaluation framework — currently built for `msbuild-skills` — to also evaluate the `unittest` plugin. The goal is maximum code reuse across plugins while maintaining independent pipelines, and to define good evaluation test cases for the `dotnet-unittest` skill.

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Shared scripts, separate workflows** | `run-scenario.ps1`, `evaluate-response.ps1`, `generate-summary.ps1`, `parse-copilot-stats.ps1` are plugin-agnostic — reuse as-is. Each plugin gets its own GitHub Actions workflow file. |
| **Parameterize plugin name/path in scripts** | Currently hardcoded to `msbuild-skills`. Replace with mandatory `-PluginName`, `-PluginPath`, `-ScenariosBaseDir` parameters. |
| **Scenarios organized by plugin** | `evaluation/scenarios/msbuild/` and `evaluation/scenarios/unittest/` — clean grouping under a shared parent. |
| **Separate results directories per plugin** | Results go to `evaluation/results/<plugin>-<run-id>/` so they don't collide. |
| **Rename workflow files** | `copilot-skills-evaluation.yml` → `eval-msbuild.yml` for consistency with new `eval-unittest.yml`. |
| **Evaluation of generated test quality** | The unittest skill generates code — evaluation should check compilability, framework correctness, coverage quality, and adherence to best practices, not just textual explanation quality. |

---

## 2. Architecture Changes

### 2.1 Current → Proposed Architecture

```
evaluation/
├── scenarios/
│   ├── msbuild/            ← msbuild-skills scenarios (moved from current location)
│   │   ├── bin-obj-clash/
│   │   └── generated-file-include/
│   └── unittest/           ← NEW: unittest scenarios
│       ├── calculator-xunit/
│       └── order-service-mstest/
├── scripts/                ← shared pipeline scripts (parameterized)
│   ├── run-scenario.ps1         (parameterized: -PluginName, -PluginPath, -ScenariosDir)
│   ├── evaluate-response.ps1    (parameterized: -ScenariosBaseDir)
│   ├── parse-copilot-stats.ps1  (already plugin-agnostic)
│   └── generate-summary.ps1     (already plugin-agnostic)
├── results/                ← run outputs (organized by plugin)
│   ├── msbuild-<run-id>/
│   └── unittest-<run-id>/
.github/workflows/
├── eval-msbuild.yml        ← renamed from copilot-skills-evaluation.yml
└── eval-unittest.yml       ← NEW
```

---

## 3. Script Changes

### 3.1 `run-scenario.ps1` — Add Plugin Parameters

Current hardcoded values:
```powershell
$pluginName = "msbuild-skills"                    # line 230
$pluginPath = Join-Path $RepoRoot "msbuild-skills" # line 231
```

**Change**: Replace hardcoded values with mandatory parameters:

```powershell
param(
    # ... existing params ...
    [Parameter(Mandatory)]
    [string]$PluginName,

    [Parameter(Mandatory)]
    [string]$PluginPath,

    [string]$ScenariosBaseDir        # defaults to evaluation/scenarios/<PluginName>
)

# Default ScenariosBaseDir
if (-not $ScenariosBaseDir) {
    $ScenariosBaseDir = Join-Path $RepoRoot "evaluation\scenarios\$PluginName"
}
```

Both workflows must pass these explicitly.

### 3.2 `evaluate-response.ps1` — Add ScenariosBaseDir Parameter

Currently uses:
```powershell
$scenarioBaseDir = Join-Path $RepoRoot "evaluation\scenarios\$ScenarioName"
```

**Change**: Add mandatory `-ScenariosBaseDir` parameter:

```powershell
param(
    # ... existing params ...
    [Parameter(Mandatory)]
    [string]$ScenariosBaseDir
)

$scenarioBaseDir = Join-Path $ScenariosBaseDir $ScenarioName
```

### 3.3 `generate-summary.ps1` — Add Plugin Name to Output

`generate-summary.ps1` currently produces a summary with no indication of which plugin was evaluated. Add an optional `-PluginName` parameter so the summary title/header includes the plugin name (e.g. *"Copilot Skills Evaluation — unittest"*).

### 3.4 `parse-copilot-stats.ps1` — No Changes

Already plugin-agnostic.

---

## 4. Workflow Changes

### 4.1 Msbuild Workflow: `eval-msbuild.yml` (renamed from `copilot-skills-evaluation.yml`)

Rename and update to pass the new mandatory parameters:

```yaml
- name: Run Vanilla / Skilled
  run: |
    pwsh -File ./evaluation/scripts/run-scenario.ps1 `
      -ScenarioName $scenario `
      -RunType "vanilla" `
      -ResultsDir "evaluation/results/$env:RUN_ID" `
      -PluginName "msbuild-skills" `
      -PluginPath "${{ github.workspace }}/msbuild-skills" `
      -ScenariosBaseDir "evaluation/scenarios/msbuild"
```

Trigger paths updated to `msbuild-skills/**`, `evaluation/scenarios/msbuild/**`, `evaluation/scripts/**`.

### 4.2 New Workflow: `eval-unittest.yml`

Structurally identical to the msbuild one, parameterized for unittest:

| Property | Value |
|-----------|-------|
| Trigger paths | `unittest/**`, `evaluation/scenarios/unittest/**`, `evaluation/scripts/**` |
| Plugin name | `unittest` |
| Plugin path | `${{ github.workspace }}/unittest` |
| Scenarios dir | `evaluation/scenarios/unittest` |
| Scenario discovery | `Get-ChildItem "evaluation/scenarios/unittest" -Directory` |

---

## 5. Unittest Evaluation Scenarios

### Design Principles for Unittest Scenarios

Unlike msbuild scenarios (which test diagnosis of build problems), unittest scenarios test **code generation quality**. The scenario provides:
- A production C# project with classes to test
- A test project (with a framework already referenced, but no test code yet)
- A `prompt.txt` asking Copilot to generate unit tests

The evaluator grades the generated tests against an `expected-output.md` rubric that covers:
- Framework detection correctness
- Test structure and naming conventions
- Edge case coverage
- Mocking usage (no fakes/stubs)
- Compilability (correct usings, attributes, assertions)
- AAA pattern adherence

### Scenario 1: `calculator-xunit`

**Purpose**: Test generation for a straightforward utility class using xUnit. Tests the skill's ability to detect xUnit, generate parameterized tests with `[Theory]`/`[InlineData]`, handle edge cases for numeric operations, and test exception paths.

**Scenario files**:

```
scenarios-unittest/calculator-xunit/
├── expected-output.md
├── scenario/
│   ├── Calculator.sln
│   ├── src/
│   │   └── Calculator/
│   │       ├── Calculator.csproj
│   │       └── MathService.cs        # Simple calculator with Add, Divide, Factorial
│   ├── tests/
│   │   └── Calculator.Tests/
│   │       └── Calculator.Tests.csproj  # xUnit + Moq referenced, no test files
│   └── prompt.txt
```

**`MathService.cs`** — Production code with clear testable methods:
```csharp
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
```

**`prompt.txt`**:
```
Generate comprehensive unit tests for the MathService class in the Calculator project. Put the tests in the existing Calculator.Tests project.
```

**`expected-output.md`** key rubric points:
- Detects xUnit framework from the test project
- Uses `[Fact]` for single-case tests, `[Theory]` + `[InlineData]` for parameterized
- Uses `Assert.Equal`, `Assert.True/False`, `Assert.Throws<T>`
- Tests `Add`: normal cases, overflow (checked arithmetic throws `OverflowException`)
- Tests `Divide`: normal, divide-by-zero exception (validates message), edge cases like `NaN`, infinity inputs
- Tests `Factorial`: 0, 1, normal, negative (exception), large values (overflow)
- Tests `IsPrime`: negatives, 0, 1, 2, small primes, composites, larger primes
- Naming: `MethodName_Condition_ExpectedOutcome`
- AAA pattern in every test
- No fake classes created

### Scenario 2: `order-service-mstest`

**Purpose**: Test generation for a class with **dependencies that need mocking** using MSTest. This is the more challenging scenario — it tests the skill's ability to detect MSTest, use Moq for dependency mocking, generate tests for async methods, handle nullable reference types, and avoid creating stub/fake classes.

**Scenario files**:

```
scenarios-unittest/order-service-mstest/
├── expected-output.md
├── scenario/
│   ├── OrderSystem.sln
│   ├── src/
│   │   └── OrderSystem/
│   │       ├── OrderSystem.csproj       # net8.0, nullable enabled
│   │       ├── IOrderRepository.cs
│   │       ├── INotificationService.cs
│   │       └── OrderProcessor.cs        # Class with injected dependencies
│   ├── tests/
│   │   └── OrderSystem.Tests/
│   │       └── OrderSystem.Tests.csproj  # MSTest + Moq referenced, no test files
│   └── prompt.txt
```

**`OrderProcessor.cs`** — Production code with DI, async methods, business logic:
```csharp
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
```

**`prompt.txt`**:
```
Generate comprehensive unit tests for the OrderProcessor class in the OrderSystem project. Put the tests in the existing OrderSystem.Tests project.
```

**`expected-output.md`** key rubric points:
- Detects MSTest framework from the test project
- Uses `[TestClass]`, `[TestMethod]`, `[DataRow]` attributes correctly
- Uses `Assert.AreEqual`, `Assert.IsTrue`, `Assert.ThrowsExceptionAsync<T>`
- **Mocking**: Uses Moq to mock `IOrderRepository` and `INotificationService` — does NOT create stub/fake implementations
- Tests constructor: null arguments throw `ArgumentNullException`
- Tests `ProcessOrderAsync`:
  - Null order → `ArgumentNullException`
  - Empty items → `ArgumentException`
  - Zero/negative quantity → `ArgumentException`
  - Total > 10,000 → returns failure result (does NOT save or notify)
  - Valid order → returns success, verifies repository save and notification were called
  - Cancellation token propagation
- Async test methods (`async Task` return type)
- Uses `[TestInitialize]` for common mock setup
- Naming: `MethodName_Condition_ExpectedOutcome`
- AAA pattern in every test
- No fake/stub/dummy classes — exclusively Moq

---

## 6. Implementation Plan

### Phase 1: Reorganize and Parameterize

| # | Task | Files Changed |
|---|------|--------------|
| 1 | Move `evaluation/scenarios/bin-obj-clash/` and `generated-file-include/` into `evaluation/scenarios/msbuild/` | Directory move |
| 2 | Add mandatory `-PluginName`, `-PluginPath`, `-ScenariosBaseDir` params to `run-scenario.ps1` | `evaluation/scripts/run-scenario.ps1` |
| 3 | Add mandatory `-ScenariosBaseDir` param to `evaluate-response.ps1` | `evaluation/scripts/evaluate-response.ps1` |
| 4 | Add optional `-PluginName` param to `generate-summary.ps1`, include plugin name in summary header | `evaluation/scripts/generate-summary.ps1` |
| 5 | Rename `copilot-skills-evaluation.yml` → `eval-msbuild.yml`, update params and paths | `.github/workflows/eval-msbuild.yml` |
| 6 | Update `evaluation/README.md` to reflect new `scenarios/msbuild/` and `scenarios/unittest/` layout, parameterized scripts, and multi-plugin instructions | `evaluation/README.md` |

### Phase 2: Create Unittest Scenarios

| # | Task | Files Created |
|---|------|--------------|
| 7 | Create `evaluation/scenarios/unittest/calculator-xunit/` scenario files | Solution, csproj, source, prompt, expected-output |
| 8 | Create `evaluation/scenarios/unittest/order-service-mstest/` scenario files | Solution, csproj, source, prompt, expected-output |

### Phase 3: Create Unittest Workflow

| # | Task | Files Created |
|---|------|--------------|
| 9 | Create `.github/workflows/eval-unittest.yml` | New workflow |

### Phase 4: Validation

| # | Task |
|---|------|
| 10 | Run msbuild evaluation locally — verify it works with new paths |
| 11 | Run unittest evaluation locally — verify end-to-end |
| 12 | Verify both workflows trigger independently on correct path changes |

---

## 7. Risk & Considerations

| Risk | Mitigation |
|------|-----------|
| Unittest eval is harder to grade — it's code generation, not diagnosis | The expected-output rubric focuses on structural qualities (framework detection, mocking, naming, coverage) rather than exact code matching. The LLM-as-judge evaluator is well-suited for this. |
| Generated tests might not compile | The rubric penalizes non-compilable output. Future enhancement: add a post-step that runs `dotnet build` on the generated tests. |
| Scenario prompt is too vague / too specific | Start with clear, focused prompts. Iterate based on evaluation results. |
| Plugin name collision in `copilot plugin list` | The `Assert-PluginState` function uses `-match` — plugin names are distinct enough (`msbuild-skills` vs `unittest`). |
| Existing msbuild evaluation breaks | Reorganize and update the msbuild workflow in the same PR so everything moves together atomically. |

---

## 8. Future Enhancements (Out of Scope)

- **Build verification step**: After skilled run, attempt `dotnet build` on the generated test project to verify compilability
- **Test execution step**: Run `dotnet test` and verify tests pass
- **Coverage measurement**: Run tests with coverage and compare skilled vs vanilla
- **Polyglot test agent evaluation**: Add scenarios for the multi-agent test generation pipeline
- **Shared workflow template**: If more plugins are added, extract a reusable workflow template
