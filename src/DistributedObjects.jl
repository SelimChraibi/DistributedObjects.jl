module DistributedObjects

    using UUIDs
    using Distributed

    export DistributedObject, localpart, close

    const objects = Dict{UUID, Any}()
    const remote_objects = Vector{}
    
    add_object(uuid::UUID, f::Function) = (objects[uuid] = f(); typeof(objects[uuid]))
    remove_object(uuid::UUID) = delete!(objects, uuid)
    
    """
        DistributedObject{T}(f::Function; pids=workers()::Vector{Int64})

    Make a reference to objects of type `T` storred on processes `pids`.
    `f` is a function that when executed on a `pid` in `pids` must return an implementation of an object of type `T`.
    The default `pids` are the worker processes.
    """
    struct DistributedObject{T}
        refs::Dict{Int64,UUID}
        function DistributedObject(f::Function; pids=workers()::Vector{Int64})
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
    end

    """
        DistributedObject{T}(f::Function, pid::Int64)

    Make a reference to an object of type `T` storred on process `pid`.
    `f` is a function that when executed on `pid` must return an implementation of an object of type `T`.
    """
    DistributedObject(f::Function, pid::Int64) = DistributedObject((pid)->f(), pids=[pid])

    Base.eltype(::Type{DistributedObject{T}}) where {T} = T

    
    """
        localpart(ro::DistributedObject{T}) where T
    

    If there is one, returns the object referenced by `ro` and storred on the current process. 
    """
    function localpart(ro::DistributedObject{T}) where T
        if haskey(ro.refs, myid())
            return objects[ro.refs[myid()]]::T
        else
            error("No localpart on process $(myid())")
        end
    end

    """
        Base.close(ro::DistributedObject)

    Remove all the remote object.
    """
    function Base.close(ro::DistributedObject) 
        @sync for pid in keys(ro.refs)
            @async remote_do(remove_object, pid, ro.refs[pid])
        end     
        empty!(ro.refs)
        return nothing
    end 
end
