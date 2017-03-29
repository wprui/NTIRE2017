require 'nn'

--------------------------------------------------------------------------
-- Below are list of common modules used in various architectures.
-- Thoses are defined as global variables in order to make other codes uncluttered.
--------------------------------------------------------------------------
seq = nn.Sequential
conv = nn.SpatialConvolution
deconv = nn.SpatialFullConvolution
relu = nn.ReLU
prelu = nn.PReLU
rrelu = nn.RReLU
elu = nn.ELU
leakyrelu = nn.LeakyReLU
bnorm = nn.SpatialBatchNormalization
avgpool = nn.SpatialAveragePooling
shuffle = nn.PixelShuffle
pad = nn.Padding
concat = nn.ConcatTable
id = nn.Identity
cadd = nn.CAddTable
join = nn.JoinTable
mulc = nn.MulConstant

function act(actParams, nOutputPlane)
    local nOutputPlane = actParams.nFeat or nOutputPlane
    local type = actParams.actType

    if type == 'relu' then
        return relu(true)
    elseif type == 'prelu' then
        return prelu(nOutputPlane)
    elseif type == 'rrelu' then
        return rrelu(actParams.l, actParams.u, true)
    elseif type == 'elu' then
        return elu(actParams.alpha, true)
    elseif type == 'leakyrelu' then
        return leakyrelu(actParams.negval, true)
    else
        error('unknown activation function!')
    end
end

function addSkip(model, global)

    local model = seq()
        :add(concat()
            :add(model)
            :add(id()))
        :add(cadd(true))

    -- global skip or local skip connection of residual block
    model:get(2).global = global or false

    return model
end

function upsample(scale, method, nFeat, actParams)
    local scale = scale or 2
    local method = method or 'espcnn'
    local nFeat = nFeat or 64

    local actType = actParams.actType
    local l, u = actParams.l, actParams.u
    local alpha, negval = actParams.alpha, actParams.negval
    actParams.nFeat = nFeat

    local model = seq()
    if method == 'deconv' then
        if scale == 2 then
            model:add(deconv(nFeat,nFeat, 6,6, 2,2, 2,2))
            model:add(act(actParams))
        elseif scale == 3 then
            model:add(deconv(nFeat,nFeat, 9,9, 3,3, 3,3))
            model:add(act(actParams))
        elseif scale == 4 then
            model:add(deconv(nFeat,nFeat, 6,6, 2,2, 2,2))
            model:add(act(actParams))
            model:add(deconv(nFeat,nFeat, 6,6, 2,2, 2,2))
            model:add(act(actParams))
        end
    elseif method == 'espcnn' then  -- Shi et al., 'Real-Time Single Image and Video Super-Resolution Using an Efficient Sub-Pixel Convolutional Neural Network'
        if scale == 2 then
            model:add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
            model:add(shuffle(2))
            model:add(act(actParams))
        elseif scale == 3 then
            model:add(conv(nFeat,9*nFeat, 3,3, 1,1, 1,1))
            model:add(shuffle(3))
            model:add(act(actParams))
        elseif scale == 4 then
            model:add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
            model:add(shuffle(2))
            model:add(act(actParams))
            model:add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
            model:add(shuffle(2))
            model:add(act(actParams))
        end
    end

    return model
end

function upsample_wo_act(scale, method, nFeat)
    local scale = scale or 2
    local method = method or 'espcnn'
    local nFeat = nFeat or 64

    if method == 'deconv' then
        if scale == 2 then
            return deconv(nFeat,nFeat, 6,6, 2,2, 2,2)
        elseif scale == 3 then
            return deconv(nFeat,nFeat, 9,9, 3,3, 3,3)
        elseif scale == 4 then
            return seq()
                :add(deconv(nFeat,nFeat, 6,6, 2,2, 2,2))
                :add(deconv(nFeat,nFeat, 6,6, 2,2, 2,2))
        end
    elseif method == 'espcnn' then  -- Shi et al., 'Real-Time Single Image and Video Super-Resolution Using an Efficient Sub-Pixel Convolutional Neural Network'
        if scale == 2 then
            return seq()
                :add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
                :add(shuffle(2))
        elseif scale == 3 then
            return seq()
                :add(conv(nFeat,9*nFeat, 3,3, 1,1, 1,1))
                :add(shuffle(3))
        elseif scale == 4 then
            return seq()
                :add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
                :add(shuffle(2))
                :add(conv(nFeat,4*nFeat, 3,3, 1,1, 1,1))
                :add(shuffle(2))
        end
    end
end

function resBlock(nFeat, addBN, actParams, scaleRes)
    local nFeat = nFeat or 64
    local scaleRes = (scaleRes and scaleRes ~= 1) and scaleRes or false

    actParams.nFeat = nFeat

    if addBN then
        return addSkip(seq()
            :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
            :add(bnorm(nFeat))
            :add(act(actParams))
            :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
            :add(bnorm(nFeat)))
    else
        if scaleRes then 
            return addSkip(seq()
                :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
                :add(act(actParams))
                :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
                :add(mulc(scaleRes, true)))
        else
            return addSkip(seq()
                :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
                :add(act(actParams))
                :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1)))
        end
    end
end

function cbrcb(nFeat, addBN, actParams)
    local nFeat = nFeat or 64
    actParams.nFeat = nFeat

    return seq()
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
        :add(bnorm(nFeat))
        :add(act(actParams))
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
        :add(bnorm(nFeat))
end

function crc(nFeat, actParams)
    local nFeat = nFeat or 64
    actParams.nFeat = nFeat

    return seq()
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
        :add(act(actParams))
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
end

function brcbrc(nFeat, actParams)
    return seq()
        :add(bnorm(nFeat))
        :add(act(actParams))
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
        :add(bnorm(nFeat))
        :add(act(actParams))
        :add(conv(nFeat,nFeat, 3,3, 1,1, 1,1))
end

local MultiSkipAdd, parent = torch.class('nn.MultiSkipAdd', 'nn.Module')

function MultiSkipAdd:__init(ip)
    parent.__init(self)
    self.inplace = ip
end

--This function takes the input like {Skip, {Output1, Output2, ...}}
--and returns {Output1 + Skip, Output2 + Skip, ...}
--It also supports in-place calculation

function MultiSkipAdd:updateOutput(input)
    self.output = {}

    if self.inplace then
        for i = 1, #input[2] do
            self.output[i] = input[2][i]
        end
    else
        for i = 1, #input[2] do
            self.output[i] = input[2][i]:clone()
        end
    end

    for i = 1, #input[2] do
        self.output[i]:add(input[1])
    end
    
    return self.output
end

function MultiSkipAdd:updateGradInput(input, gradOutput)
    self.gradInput = {gradOutput[1]:clone():fill(0), {}}

    if self.inplace then
        for i = 1, #input[2] do
            self.gradInput[1]:add(gradOutput[i])
            self.gradInput[2][i] = gradOutput[i]
        end
    else
        for i = 1, #input[2] do
            self.gradInput[1]:add(gradOutput[i])
            self.gradInput[2][i] = gradOutput[i]:clone()
        end
    end

    return self.gradInput
end

--this is a test code for nn.MultiSkipAdd
--[[
local conv = nn.SpatialConvolution(1, 1, 3, 3)
--local conv = nn.Identity()
local ref = nn.Sequential()
local cat = nn.ConcatTable()
local b1 = nn.Sequential()
    :add(nn.NarrowTable(1, 2))
    :add(nn.CAddTable(false))
    :add(conv:clone())
local b2 = nn.Sequential()
    :add(nn.ConcatTable()
        :add(nn.SelectTable(1))
        :add(nn.SelectTable(3)))
    :add(nn.CAddTable(false))
    :add(conv:clone())
ref
    :add(nn.FlattenTable())
    :add(cat
        :add(b1)
        :add(b2))

local comp = nn.Sequential()
    :add(nn.MultiSkipAdd(true))
    :add(nn.ParallelTable()
        :add(conv:clone())
        :add(conv:clone()))

local input1 = {torch.randn(1, 1, 6, 6), {torch.randn(1, 1, 6, 6), torch.randn(1, 1, 6, 6)}}
local input2 = {input1[1]:clone(), {input1[2][1]:clone(), input1[2][2]:clone()}}

print(input1)
print(table.unpack(ref:forward(input1)))
print(table.unpack(comp:forward(input2)))

local go1 = {torch.randn(1, 1, 4, 4), torch.randn(1, 1, 4, 4)}
local go2 = {go1[1]:clone(), go1[2]:clone()}

gi1 = ref:updateGradInput(input1, go1)
gi2 = comp:updateGradInput(input2, go2)
print(gi1[1])
print(table.unpack(gi1[2]))
print(gi2[1])
print(table.unpack(gi2[2]))
]]
