require 'torch'
require 'camera'
require 'qt'
require 'qtwidget'
require 'qtuiloader'
require 'xlua'
xrequire('nnx',true)
xrequire('camera',true)

require 'torch'
require 'qt'
require 'xlua'
require 'qtwidget'
require 'qtuiloader'
xrequire('nnx',true)
xrequire('camera',true)


widget = qtuiloader.load('g.ui')
window = qt.QtLuaPainter(widget.frame)
cam = image.Camera{}

function display()
	frame = cam:forward()
	image.display{image = frame,win = window,zoom = 1}
end

timer = qt.QTimer()


widget:show()

while true do
	display()
end


