module maxpooling2d
    using LoopVectorization, HDF5, .Threads

    mutable struct MaxPooling2D
        save_layer::Any
        load_layer::Any
        activate::Any
        initialize::Any
        update::Any

        input_size::Int64
        layer_size::Int64
        activation_function::Module

        unit_size::Tuple{Int64, Int64}
        input2D_size::Tuple{Int64, Int64}
        kernel_size::Tuple{Int64, Int64}
        step_x::Int64
        step_y::Int64

        weights::Array{Int64}
        value::Array{Float32}
        output::Array{Float32}
        ∇biases::Array{Float32}
        propagation_units::Array{Float32}

        function MaxPooling2D(;input_filter::Int64, input_size::Int64, input2D_size::Tuple{Int64, Int64}, kernel_size::Tuple{Int64, Int64}, step_x::Int64=kernel_size[2], step_y::Int64=kernel_size[1], activation_function::Module, reload::Bool=false)
            if reload
                return new(save_MaxPooling2D, load_MaxPooling2D, activate_MaxPooling2D, init_MaxPooling2D, update_MaxPooling2D)
            end

            conv_num_per_row = (input2D_size[2]-kernel_size[2])÷step_x+1
            conv_num_per_col = (input2D_size[1]-kernel_size[1])÷step_y+1
            unit_size = (conv_num_per_row*conv_num_per_col, input_size÷input_filter)
            new(save_MaxPooling2D, load_MaxPooling2D, activate_MaxPooling2D, init_MaxPooling2D, update_MaxPooling2D, input_size, conv_num_per_row*conv_num_per_col*input_filter, activation_function, unit_size, input2D_size, kernel_size, step_x, step_y)
        end
    end

    function init_MaxPooling2D(layer::MaxPooling2D, mini_batch::Int64)
        layer.weights = zeros(Int64, (layer.layer_size, mini_batch))
        layer.value = zeros(Float32, (layer.layer_size, mini_batch))
        layer.∇biases = zeros(Float32, (layer.layer_size, mini_batch))
    end

    function activate_MaxPooling2D(layer::MaxPooling2D, input::Array{Float32})
        @avx for i in axes(layer.weights, 1), j in axes(layer.weights, 2)
            layer.weights[i,j] = 0
            layer.value[i,j] = 0.0f0
        end

        conv_num_per_row = (layer.input2D_size[2]-layer.kernel_size[2])÷layer.step_x+1
        conv_num_per_col = (layer.input2D_size[1]-layer.kernel_size[1])÷layer.step_y+1
        @threads for i in 1:layer.input_size÷layer.unit_size[2]
            for b in 1:size(input, 2)
                create_value(layer, input, b, i, conv_num_per_row, conv_num_per_col)
            end
        end
        layer.output = layer.activation_function.func(layer.value)
    end

    function update_MaxPooling2D(layer::MaxPooling2D, optimizer::String, Last_Layer_output::Array{Float32}, Next_Layer_propagation_units::Array{Float32}, α::Float64, parameters::Tuple, direction::Int64=0)
        layer.activation_function.get_∇biases!(layer.∇biases, layer.value, Next_Layer_propagation_units)
        PU_MaxPooling2D(layer, layer.∇biases)
    end

    function PU_MaxPooling2D(layer::MaxPooling2D, ∇biases::Array{Float32})
        batch_size = size(∇biases, 2)
        layer.propagation_units = zeros(Float32, (layer.input_size, batch_size))
        if layer.step_x>=layer.kernel_size[2] && layer.step_y>=layer.kernel_size[1]
            @avx for b in 1:batch_size
                for x in axes(layer.weights, 1)
                    layer.propagation_units[layer.weights[x,b],b] = ∇biases[x,b]
                end
            end
        else
            @threads for i in 1:layer.input_size
                for b in 1:batch_size
                    for x in findall(y->y==i, layer.weights[:,b])
                        layer.propagation_units[i,b] += ∇biases[x,b]
                    end
                end
            end
        end
    end


    function create_value(layer::MaxPooling2D, input::Array{Float32}, b::Int64, i::Int64, conv_num_per_row::Int64, conv_num_per_col::Int64)
        for l in 0:layer.unit_size[1]-1
            index = layer.step_x*(l%conv_num_per_row) + layer.input2D_size[2]*layer.step_y*(l÷conv_num_per_row)
            max_value = -Inf
            register = 0
            for j in 1:layer.kernel_size[1]
                for k in 1:layer.kernel_size[2]
                    if input[(i-1)*layer.unit_size[2]+index+k,b]>=max_value
                        max_value = input[(i-1)*layer.unit_size[2]+index+k,b]
                        register = (i-1)*layer.unit_size[2]+index+k
                    end
                end
                index += layer.input2D_size[2]
            end
            layer.value[(i-1)*layer.unit_size[1]+l+1, b] = input[register]
            layer.weights[(i-1)*layer.unit_size[1]+l+1, b] = register
        end
    end

    function save_MaxPooling2D(layer::MaxPooling2D, file::Any, id::Int64)
        write(file, string(id), "MaxPooling2D")
        write(file, string(id)*"input_size", layer.input_size)
        write(file, string(id)*"layer_size", layer.layer_size)
        write(file, string(id)*"unit_size", collect(layer.unit_size))
        write(file, string(id)*"input2D_size", collect(layer.input2D_size))
        write(file, string(id)*"kernel_size", collect(layer.kernel_size))
        write(file, string(id)*"step_x", layer.step_x)
        write(file, string(id)*"step_y", layer.step_y)
        write(file, string(id)*"activation_function", layer.activation_function.get_name())
    end

    function load_MaxPooling2D(layer::MaxPooling2D, file::Any, id::Int64)
        layer.unit_size = Tuple(read(file, string(id)*"unit_size"))
        layer.input2D_size = Tuple(read(file, string(id)*"input2D_size"))
        layer.input_size = read(file, string(id)*"input_size")
        layer.layer_size = read(file, string(id)*"layer_size")
        layer.kernel_size = Tuple(read(file, string(id)*"kernel_size"))
        layer.step_x = read(file, string(id)*"step_x")
        layer.step_y = read(file, string(id)*"step_y")
    end
end
