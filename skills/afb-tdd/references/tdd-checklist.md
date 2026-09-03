# TDD Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the right reason (feature missing, not a typo)
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output is pristine — no errors or warnings
- [ ] Tests use real code (mocks only where unavoidable)
- [ ] Edge cases and error paths are covered
- [ ] Each test covers one behaviour (no AND in the test name)
- [ ] Bug fixes have a test that would have caught the original bug
- [ ] The sceptic ran at every Red and Green checkpoint (or `--no-sceptic` was explicitly set); every finding was fixed or rebutted in the report
- [ ] The deletion question: if the code under test were deleted, would every new test fail?

If you cannot honestly and thoroughly check all the boxes, then you did not TDD. Start over.

## When Stuck

| Problem | Solution |
|---|---|
| Don't know how to test it | Write the wished-for API. Write the assertion first. Ask your human partner. |
| Test is too complicated | The design is too complicated. Simplify the interface. |
| Must mock everything | Code is too coupled. Use dependency injection. |
| Test setup is huge | Extract helpers. Still complex? Simplify the design. |
| Bug found in existing code | Write a failing test reproducing it first, then fix. Never fix bugs without a test. |
| A test fails and you don't know why | Classify it: TEST wrong vs CODE wrong. Prove the classification with two independent pieces of evidence before changing either. Undetermined? Stop and ask. |
