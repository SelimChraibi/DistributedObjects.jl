module DistributedObjects

    using UUIDs
    using Distributed

    export DistributedObject, delete!, close, where

    const objects = Dict{UUID, Any}()
    const remote_objects = Vector{}
    
    add_object(uuid::UUID, f::Function) = (objects[uuid] = f(); typeof(objects[uuid]))
    remove_object(uuid::UUID) = delete!(objects, uuid)
    
    
    struct DistributedObject{T}
        refs::Dict{Int64,UUID}
        """
            DistributedObject{T}() where T

        Create an empty `DistributedObject` which will reference objects of type `T` stored on remote processes.

        For example, `DistributedObject{Int64}()`, will return a distributed object capable of referencing `Int64` objects.
        """
        DistributedObject{T}() where T = new(Dict{Int64,UUID}())
        
        """
            DistributedObject{T}(f::Function; pids=workers()::Vector{Int64})

        Make a reference to objects of type `T` stored on processes `pids`.
        `f` is a function that when executed on a `pid` in `pids` must return an implementation of an object of type `T`.
        The default `pids` are the worker processes.

        For example, `DistributedObject((pid)->pid * ones(2); pids=[2,3])`, will return a distributed object referencing a vector `[2,2]` and `[3,3]` stored on workers 2 and 3 respectively.
        """
        function DistributedObject(f::Function; pids=workers()::Vector{Int64})
            @assert !isempty(pids) "Please make sure worker process have been launched and provide a non empty `pids`"
            refs = Dict{Int64,UUID}()
            types = Vector{Type}(undef, length(pids))
            @sync for (i,pid) in enumerate(pids)
                @async begin
                    uuid = uuid1()
                    refs[pid] = uuid
                    types[i] = remotecall_fetch(add_object, pid, uuid, ()->f(pid))
                end
            end
            length(types)==1 || @assert all(==(types[1]), types)
            new{types[1]}(refs)
        end

        """
            DistributedObject{T}(f::Function, pid::Int64)

        Make a reference to an object of type `T` stored on process `pid`.
        `f` is a function that when executed on `pid` must return an implementation of an object of type `T`.

        For example, `DistributedObject(()->ones(2), 4)`, will return a distributed object referencing a vector `[1,1]` stored on workers 4.
        """
        DistributedObject(f::Function, pid::Int64) = DistributedObject((pid)->f(), pids=[pid])
    end

    Base.eltype(::Type{DistributedObject{T}}) where {T} = T

    where(d::DistributedObject) = sort(collect(keys(d.refs)))

    """
        Base.setindex!(d::DistributedObject{T}, f::Function, pids::Int64...) where T

    Store the objects of type `T` returned by `f` evaluated on each process of `pids`, if they don`t already store an object.
    If `pids` has one element or less, `f` should take no argument, otherwise, it takes a `pid::Int64` as an argument.
    If no `pids` is given, the object is stored in the current process.
    """
    function Base.setindex!(d::DistributedObject{T}, f::Function, pids::Int64...) where T
        isempty(pids) && (pids = [myid()])
        length(pids) == 1 ? _f(pid) = f() : _f = f # Account for the case when `f` takes no argument

        @sync for pid in pids
            @async begin
                haskey(d.refs, pid) && delete!(d, pid)
                uuid = uuid1()
                d.refs[pid] = uuid
                pid==myid() ? add_object(uuid, ()->_f(pid)) : remote_do(add_object, pid, uuid, ()->_f(pid))
            end
        end
    end

    
    
    """
        Base.getindex(d::DistributedObject{T}, pids::Int64...) where T

    Retrieve the remote object(s) stored at the process(es) `pids` if they exist.
    If no `pids` is given, the object stored in the current process is returned.
    Warning: retrieving remote objects will create communication costs.
    """
    function Base.getindex(d::DistributedObject{T}, pids::Int64...) where T
        isempty(pids) && (pids = [myid()])
        [pids...] != [myid()] && (remote_pids = filter!(e->e!=myid(),[pids...]))

        output = Vector{T}(undef, length(pids))
        @sync for (i, pid) in enumerate(pids)
            @async begin 
                @assert haskey(d.refs, pid) "This distributed object has no remote object on process $pid."
                output[i] = pid==myid() ? objects[d.refs[myid()]] : fetch(@spawnat pid objects[d.refs[myid()]])
            end
        end
        length(pids) == 1 ? output[1] : output
    end
    
    """
        Base.delete!(d::DistributedObject, pid::Int64)

    Remove the remote object stored on process `pid`.
    """
    function Base.delete!(d::DistributedObject, pid::Int64) 
        remote_do(remove_object, pid, d.refs[pid])
        delete!(d.refs, pid)
        return nothing
    end 

    """
        Base.close(d::DistributedObject)

    Remove all the remote objects.
    """
    function Base.close(d::DistributedObject) 
        @sync for pid in keys(d.refs)
            @async remote_do(remove_object, pid, d.refs[pid])
        end     
        empty!(d.refs)
        return nothing
    end 
end