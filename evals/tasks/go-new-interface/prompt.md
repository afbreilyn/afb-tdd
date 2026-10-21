Introduce an `IDGenerator` interface in a new package `idgen`, with one method:

    NewID() string

Add a real implementation, `idgen.Sequential`, that returns `u-1`, `u-2`, `u-3`, … in order, starting again from `u-1` for each new `Sequential`. Nothing needs to use it yet.
