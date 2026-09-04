# Java Test Conventions

## Test Class Structure

Use `@ExtendWith(MockitoExtension.class)` with `@Mock` fields and manual constructor injection in `@BeforeEach`. Never use `@InjectMocks` or field `@Autowired` in unit tests.

```java
@ExtendWith(MockitoExtension.class)
class MyServiceTest {
  @Mock private MyRepository repository;
  @Mock private OtherService otherService;

  private MyService testClass;

  @BeforeEach
  void setup() {
    testClass = new MyService(repository, otherService);
  }
}
```
## Mockito Rules

**Never use `any()`** — always pass a concrete argument. `any()` lets wrong values pass silently.

```java
// ✅ GOOD: fails if wrong status is used
when(repository.findByStatus(Status.ACTIVE)).thenReturn(activeEntities);

// ❌ BAD: passes even if wrong status is passed
when(repository.findByStatus(any())).thenReturn(activeEntities);
```

**Never use `lenient()`** — only stub what is actually called in each test. Unused stubs hide dead code.

**Skip `verify()` when the method is stubbed and its return value drives the assertion** — if the method isn't called, the test will already fail because the stub won't return the expected value.

```java
// ✅ GOOD: verify is redundant here
when(repository.findById(id)).thenReturn(Optional.of(entity));
var result = testClass.process(id);
assertThat(result).usingRecursiveComparison().isEqualTo(expected);

// Reserve verify() for side effects: void methods, call counts, argument capture
verify(eventPublisher).publish(new LiquidationEvent(id));
```

## AssertJ Assertions

**Prefer recursive comparison over field-by-field.** This catches new fields automatically.

```java
// ✅ GOOD: new fields on SomeResult are automatically tested
assertThat(testClass.myMethod(arg1, arg2))
    .usingRecursiveComparison()
    .isEqualTo(new SomeResult("a", "b"));

// ❌ BAD: misses new fields silently
assertThat(actual.getField1()).isEqualTo("a");
assertThat(actual.getField2()).isEqualTo("b");
```

**Inline the expected object** — don't extract it to a variable above the assertion.

```java
// ✅ GOOD
assertThat(testClass.myMethod(arg1, arg2))
    .usingRecursiveComparison()
    .isEqualTo(new SomeResult("a", "b"));

// ❌ BAD: reader must scroll up
var expected = new SomeResult("a", "b");
assertThat(testClass.myMethod(arg1, arg2))
    .usingRecursiveComparison()
    .isEqualTo(expected);
```

**For collections:** use `usingRecursiveFieldByFieldElementComparator().containsExactlyInAnyOrderElementsOf(...)`, not `isEqualTo(Set.of(...))`.

```java
// ✅ GOOD
assertThat(result)
    .usingRecursiveFieldByFieldElementComparator()
    .containsExactlyInAnyOrderElementsOf(expectedObjectss);

// ❌ BAD
assertThat(result)
    .usingRecursiveComparison()
    .isEqualTo(Set.of(expectedObjects));
```

**For exceptions:** use `assertThatExceptionOfType`, not `assertThatThrownBy`.

```java
// ✅ GOOD
assertThatExceptionOfType(IllegalStateException.class)
    .isThrownBy(() -> testClass.myMethod(arg1, arg2))
    .withMessageContaining("This is an error mesage");

// ❌ BAD
assertThatThrownBy(() -> testClass.myMethod(arg1, arg2))
    .isInstanceOf(IllegalStateException.class);
```

**For happy-path constructors with nothing to assert on the result:**

```java
// ✅ GOOD
assertThatNoException()
    .isThrownBy(() -> new MyObject("valid-value"));
```

**Never use `isInstanceOf` on return values** — it only checks type, not content.

## No Comments in Test Bodies

Do not add Given/When/Then comments or section headers. The method name describes intent; the structure speaks for itself.

```java
// ❌ BAD
@Test
void process_whenValid_thenMutates() {
  // Given
  when(repository.findById(id)).thenReturn(Optional.of(entity));
  // When
  testClass.process(id);
  // Then
  verify(queue).mutate(new MyObject(id));
}

// ✅ GOOD
@Test
void process_whenValid_thenMutates() {
  when(repository.findById(id)).thenReturn(Optional.of(entity));
  testClass.process(id);
  verify(queue).mutate(new MyObject(id));
}
```

**External HTTP:** use WireMock.

## Unit vs Integration

Prefer unit tests — they're faster and cheaper in CI. Write integration tests for:
- Database interactions and queries
- Full request/response flow through the Spring context

If a unit test requires mocking more than 3–4 collaborators, consider splitting the production class rather than adding more mocks.

## Unwieldy Mock Setup is a Design Signal

If `@BeforeEach` setup is longer than any individual test, the production class is doing too much. The fix is to refactor the service, not to add more test helpers.