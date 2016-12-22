###################
# Helper function #
###################

doc"""
    has_ops(ex)

Check if has optional arguments.

```julia
has_ops(parse("@assume x ~ Normal(0, 1; :static=true)"))  # gives true
has_ops(parse("@assume x ~ Normal(0, 1)"))                # gives false
has_ops(parse("@assume x ~ Binomial(; :static=true)"))    # gives true
has_ops(parse("@assume x ~ Binomial()"))                  # gives false
```
"""
function has_ops(right)
  if length(right.args) <= 1               # check if the D() has parameters
    return false                                # Binominal() can have empty
  elseif typeof(right.args[2]) != Expr     # check if has optional arguments
    return false
  elseif right.args[2].head != :parameters # check if parameters valid
    return false
  end
  true
end

function gen_assume_ex(left, right)
  # The if statement is to deterimnet how to pass the prior.
  # It only supposrts pure symbol and Array(/Dict) now.
  if isa(left, Symbol)
    quote
      $(left) = Turing.assume(
        Turing.sampler,
        $(right),    # dDistribution
        VarInfo(          # Pure Symbol
          Symbol($(string(left)))
        )
      )
    end
  elseif length(left.args) == 2 && isa(left.args[1], Symbol)
    quote
      $(left) = Turing.assume(
        Turing.sampler,
        $(right),    # dDistribution
        VarInfo(          # Array assignment
          parse($(string(left))),           # indexing expr
          Symbol($(string(left.args[2]))),  # index symbol
          $(left.args[2])                   # index value
        )
      )
    end
  elseif length(left.args) == 2 && isa(left.args[1], Expr)
    quote
      $(left) = Turing.assume(
        Turing.sampler,
        $(right),    # dDistribution
        VarInfo(          # Array assignment
          parse($(string(left))),           # indexing expr
          Symbol($(string(left.args[1].args[2]))),  # index symbol
          $(left.args[1].args[2]),                  # index value
          Symbol($(string(left.args[2]))),  # index symbol
          $(left.args[2])                   # index value
        )
      )
    end
  elseif length(left.args) == 3
    quote
      $(left) = Turing.assume(
        Turing.sampler,
        $(right),    # dDistribution
        VarInfo(          # Array assignment
          parse($(string(left))),           # indexing expr
          Symbol($(string(left.args[2]))),  # index symbol
          $(left.args[2]),                  # index value
          Symbol($(string(left.args[3]))),  # index symbol
          $(left.args[3])                   # index value
        )
      )
    end
  end
end

#################
# Overload of ~ #
#################

macro ~(left, right)
  # Deal with additional arguments for distribution
  if has_ops(right)
    # If static is set
    if right.args[2].args[1].args[1] == :static && right.args[2].args[1].args[2] == :true
      # Do something
    end
    # If param is set
    if right.args[2].args[1].args[1] == :param && right.args[2].args[1].args[2] == :true
      # Do something
    end
    # Remove the extra argument
    splice!(right.args, 2)
  end

  if isa(left, Real)                  # value
    # Call observe
    esc(
      quote
        Turing.observe(
          Turing.sampler,
          $(right),   # Distribution
          $(left)     # Data point
        )
      end
    )
  else
    local sym
    if isa(left, Symbol)              # symbol
      sym = left
    elseif length(left.args) == 2 && isa(left.args[1], Symbol)  # vector
      sym = left.args[1]
    elseif length(left.args) == 2 && isa(left.args[1], Expr)    # array of arry
      sym = left.args[1].args[1]
    elseif length(left.args) == 3
      sym = left.args[1]
    end
    esc(
      quote
        if isdefined(Symbol($(string(sym))))
          # Call observe
          Turing.observe(
            Turing.sampler,
            $(right),   # Distribution
            $(left)     # Data point
          )
        else
          # Call assume
          $(gen_assume_ex(left, right))
        end
      end
    )
  end
end

doc"""
    predict(ex...)

Operation for defining the the variable(s) to return.

Usage:

```julia
@predict x y z
```

Here `x`, `y`, `z` are symbols.
"""
macro predict(ex...)
  dprintln(1, "marco predicting...")
  ex_funcs = Expr(:block)
  for i = 1:length(ex)
    @assert typeof(ex[i]) == Symbol
    sym = string(ex[i])
    push!(
      ex_funcs.args,
      :(ct = current_task();
        Turing.predict(
          Turing.sampler,
          Symbol($sym), get(ct, $(ex[i]))
        )
      )
    )
  end
  esc(ex_funcs)
end

doc"""
    model(name, fbody)

Wrapper for models.

Usage:

```julia
@model f body
```

Example:

```julia
@model gauss begin
  @assume s ~ InverseGamma(2,3)
  @assume m ~ Normal(0,sqrt(s))
  @observe 1.5 ~ Normal(m, sqrt(s))
  @observe 2.0 ~ Normal(m, sqrt(s))
  @predict s m
end
```
"""
macro model(name, fbody)
  dprintln(1, "marco modelling...")
  # Functions defined via model macro have an implicit varinfo array.
  # This varinfo array is useful is task cloning.

  # Turn f into f() if necessary.
  fname = isa(name, Symbol) ? Expr(:call, name) : name
  ex = Expr(:function, fname, fbody)

  # Assign data locally
  local_assign_ex = quote
    if isdefined(Symbol("data"))
      for k in keys(data)
        ex = Expr(Symbol("="), k, data[k])
        eval(ex)
      end
    end
  end
  unshift!(fbody.args, local_assign_ex)

  TURING[:modelex] = ex
  return esc(ex)  # esc() makes sure that ex is resovled where @model is called
end
