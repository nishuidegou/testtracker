require 'torch'
require 'camera'
require 'qt'
require 'qtwidget'
require 'qtuiloader'
require 'xlua'
xrequire('nnx',true)
xrequire('camera',true)

torch.setdefaulttensortype('torch.FloatTensor')


widget = qtuiloader.load('gt.ui')
window = qt.QtLuaPainter(widget.frame)
cam = image.Camera{}

zoom = 1
box = 64
learn = nil

rawFrame = torch.Tensor()
input = torch.Tensor()


--------------------------------------------------------------
-- ui class
local ui = {}

--ui.resize = true

-- connect mouse pos
widget.frame.mouseTracking = true
qt.connect(qt.QtLuaListener(widget.frame),
            'sigMouseMove(int,int,QByteArray,QByteArray)',
            function (x,y)
                ui.mouse = {x=x,y=y}
            end)

-- issue learning request
qt.connect(qt.QtLuaListener(widget),
            'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
            function (...)
                if ui.mouse then
                    learn = {x=ui.mouse.x,y=ui.mouse.y,id=1}
                end
            end)

---------------------------------------------------------------            
-- display function
function display()
	--frame = cam:forward()
	image.display{image = input,win = window,zoom = zoom}

    -- draw a circle around mouse
    _mousetic_ = ((_mousetic_ or -1) + 1) % 2
    if ui.mouse and _mousetic_ == 1 then
        local color = 'blue'
        local legend = 'learning object'
        local x = ui.mouse.x
        local y = ui.mouse.y
        local w = box
        local h = box
        window:setcolor(color)
        window:setlinewidth(3)
        window:arc(x * zoom, y * zoom, h/2 * zoom, 0, 360)
        window:stroke()
        window:setfont(qt.QFont{serif=false,italic=false,size=12})
        window:moveto((x-box/2) * zoom, (y-box/2-2) * zoom)
        window:show(legend)
    end
    
    -- draw a rectangle when the mouse press
    if learn then
        local color = 'red'
        local legend = 'smr tracking rec'
        local w = box
        local h = box
        local x = ui.mouse.x
        local y = ui.mouse.y
        window:setcolor(color)
        window:setlinewidth(3)
        window:rectangle(x * zoom, y * zoom, w * zoom, h * zoom)
        window:stroke()
        window:setfont(qt.QFont{serif=false,italic=false,size=12})
        --window:moveto(x,y)
        window:show(legend)
    end

end

cam.rgb2yuv = nn.SpatialColorTransform('rgb2y')
cam.rescaler = nn.SpatialReSampling{owidth=320,oheight=240}

extension = 20
-- function getframe()
function getframe()
    rawFrame = cam:forward()
    rawFrame = rawFrame:float()

    RGBFrame = cam.rescaler:forward(rawFrame)
    YUVFrame = cam.rgb2yuv:forward(RGBFrame)

    input = torch.Tensor(YUVFrame:size(2)+2*extension,YUVFrame:size(3)+2*extension):fill(0)
    input[{{extension+1, YUVFrame:size(2)+extension}, {extension+1, YUVFrame:size(3)+extension}}] = YUVFrame[1]
end

-- function process()
function process()
    getframe()

end

timer = qt.QTimer()


-- set timer
timer = qt.QTimer()
timer.interval = 10     -- 10ms
timer.singleShot = true
qt.connect(timer,'timeout()',function() process() display() timer:start() end)

-- load widget and display use timer
widget.windowTitle = 'A simple test widget'
widget:show()
timer:start()

--[[
while true do
	display()
end
--]]


