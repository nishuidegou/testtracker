local smr_dist = assert(require("libsmrdist"))
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
downs = 2
dynamic = 0.1

-- flag
local lifetime = 0
local dynamic_th = 0
local threshold = 0
local lost = 0
local disapper = 0

rawFrame = torch.Tensor()
input = torch.Tensor()
lastPatch = torch.Tensor()
totalProb = torch.Tensor()
SMRProb = torch.Tensor()

resultsSMR = {}

classes = {'Object 1','Object 2','Object 3',
                   'Object 4','Object 5','Object 6'}

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
                print(ui.mouse.x,ui.mouse.y)
                if ui.mouse.x<320 and ui.mouse.y<240 then
                    learn = {x=ui.mouse.x,y=ui.mouse.y,id=1}
                end
            end)
widget.windowTitle = 'A simple test widget'
widget:show()
---------------------------------------------------------------            
-- display function
function display()
	--frame = cam:forward()
	image.display{image = input,win = window,zoom = zoom}

   -- draw a rectangle when the mouse press
    for _,res in ipairs(resultsSMR) do
        local color = 'red'
        local legend = res.class
        local w = res.w
        local h = res.h
        local x = res.lx
        local y = res.ty
        window:setcolor(color)
        window:setlinewidth(3)
        window:rectangle(x * zoom, y * zoom, w * zoom, h * zoom)
        window:stroke()
        window:setfont(qt.QFont{serif=false,italic=false,size=12})
        window:moveto(x*zoom,(y-2)*zoom)
        window:show('SMR tracker')
        print(w,h,x,y)
    end

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
        --print(x,y)
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

-- function SMRtracker()
function SMRtracker(patch)
    for _,res in ipairs(resultsSMR) do
        begin_x = math.max(0,res.lx - 60/downs -1)
        end_x   = math.min(SMRProb:size(2),(res.lx+60/downs))
        begin_y = math.max(0,res.ty - 50/downs -1)
        end_y   = math.min(SMRProb:size(1),(res.ty+50/downs))
    end

    if(lifetime > 0) then
        begin_x = math.max(0,begin_x-lifetime)
        end_x   = math.min(SMRProb:size(2),end_x + lifetime)
        begin_y = math.max(0,begin_y-lifetime)
        end_y   = math.min(SMRProb:size(1),end_y + lifetime)
    end
    lifetime = lifetime + 1

    SMRProb:fill(0)
    smr_dist.smr(SMRProb,input,patch,dynamic,begin_x,end_x,begin_y,end_y)
end

-- Find the max value and coordinates of a tensor
function GetMax(a)
	x,xi = torch.max(a,1)
	y,yi = torch.max(x,2) -- y = value

	x_out = yi[1][1]      -- y coord
	y_out = xi[1][x_out]  -- x coord
	return y,x_out,y_out 
end

-- function process()
function process()
    getframe()
    
    -- calculate the SMR map
    SMRProb = torch.Tensor(math.floor(input:size(1)-box)+1,math.floor(input:size(2)-box)+1):fill(0)
    if lastPatch:dim() > 0 then
        SMRtracker(lastPatch)
        value,px_nxt,py_nxt = GetMax(SMRProb)
        local lx = math.min(math.max(0,(px_nxt-1)+1),input:size(2)-box+1)
        local ty = math.min(math.max(0,(py_nxt-1)+1),input:size(1)-box+1)        

        window =8 
        SMRProb:narrow(2, math.max(px_nxt-window, 1), math.min(2*window, SMRProb:size(2)-px_nxt+window-1)):
           narrow(1, math.max(py_nxt-window, 1), math.min(2*window,SMRProb:size(1)-py_nxt+window-1)):zero()
        dynamic_th = SMRProb:max()

        -- Dynamic thresholding
        if (lost == 0) then 
          if(lx>=extension) and (ty>=extension) and (lx+box/downs)<=(input:size(2)-extension) and (ty+box/downs)<=(input:size(1)-extension-1) then
              if (disappear == 1) then 
                 threshold = 1.2 
              else
                 threshold = 1
              end 
          else 
              threshold = 1.02
              disappear = 1
          end    
       else 
          threshold = 1.25 
       end  

      -- Accept or reject the detection
      if  (value[1][1]>(threshold*dynamic_th)) or  (value[1][1]>dynamic_th+100) then

         lifetime = 0
         if (threshold == 1.25) then 
            disappear = 0
         end  
         lost = 0 
        
         local nresult = {lx=lx, ty=ty, cx=lx+box/2, cy=ty+box/2, w=box, h=box,
                    class=classes[1], id=1, source=2}                    
         table.insert(resultsSMR, nresult) 
      else 
           lost = 1   
      end
      -- Template update
      -- Do not update the template if the object is going out of the scene
      -- A better template update mechanism is necessary to handle the occlusions.  
        for _,res in ipairs(resultsSMR) do
            if(res.lx>=2*extension) and (res.ty>=2*extension) and (res.lx+box)<YUVFrame:size(3)+extension-1 and (res.ty+box)<YUVFrame:size(2)+extension-1 then
               local patchYUV = torch.Tensor(box, box):fill(0)
               patchYUV:copy(input[{ {res.ty, box+res.ty-1},{res.lx,box+res.lx-1}}])

              if lastPatch:dim() > 0 then
                  difference = (lastPatch:add(-1, patchYUV)):abs()
                  if (difference:max()/2)~=0 then
                    dynamic=(difference:max()/2)
                  end
                  lastPatch:copy(patchYUV)
               end  
            end   
        end

    end

    -- latest tracking frame
    if learn then
        ref_lx = math.min(math.max(learn.x-box/2,0),input:size(2)-box)
        ref_ty = math.min(math.max(learn.y-box/2,0),input:size(1)-box)

        local nresult = {lx=ref_lx,ty=ref_ty,w=box,h=box,class=classes[learn.id],id=learn.id,source=6}
        table.insert(resultsSMR,nresult)
        -- save a patch
        local patchYUV = torch.Tensor(box,box):fill(0)
        patchYUV:copy(input[{{ref_ty,box+ref_ty-1},{ref_lx,box+ref_lx-1}}])
        lastPatch = patchYUV:clone()
        -- done
        learn = nil     
    end
end

timer = qt.QTimer()


-- set timer
timer = qt.QTimer()
timer.interval = 10     -- 10ms
timer.singleShot = true
qt.connect(timer,'timeout()',function() process() display() timer:start() end)

-- load widget and display use timer
--widget.windowTitle = 'A simple test widget'
--widget:show()
timer:start()

--[[
while true do
	display()
end
--]]


