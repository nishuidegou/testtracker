widget = qtuiloader.load('g.ui')

local ui = {}

--ui.resize = true

-- connect mouse pos
widget.frame.mouseTracking = true
qt.connect(qt.QtLuaListener(widget.frame),
            'sigMouseMove(int,int,QByteArray,QByteArray)',
            function (x,y)
                ui.mouse = {x=x,y=y}
            end)


return ui
