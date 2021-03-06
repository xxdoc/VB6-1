Attribute VB_Name = "mSystem"
'================================================
' Module:        mSystem
' Author:        Warren Galyen
' Website:       http://www.mechanikadesign.com
' Dependencies:  clsBinaryFile.cls
' Last revision: 2006.06.26
'================================================

' History:  26 Jun 06 - Added grid texture, layer texture rotation, and normal mapping for grid

' TO DO:  - Add GUI controls for color (flame & light) parameters
'         - Add GUI controls for radius, particle count, and texture parameters

Option Base 0
Option Explicit

' Direct sound
Public DSX As clsSound

' Package system
Public cPKG As clsPackage
Public cVirtualFile As clsBinaryFile

' Global configuration
Public lngWidth As Long
Public lngHeight As Long
Public bSafeMode As Boolean

' FPS counter
Public lngFPS As Long

' Start switch
Public bOK As Boolean

' Camera distance
Public sngCamFinalDistance As Single
Public sngCamCurrentDistance As Single
Public sngCamFinalHeight As Single
Public sngCamCurrentHeight As Single

' Texture rotation feature
Public bTexRotate As Boolean

' Global lightning, grid & static objects
Public bLighting As Boolean
Public bRenderGrid As Boolean
Public bRenderStatic As Boolean
Public bReflections As Boolean
Public bTexture As Boolean
Public bWireframe As Boolean
Public bWiregrid As Boolean
Public bShade As Boolean
Public bAlphaBlend As Boolean

' DirectX core objects
Public cDX As DirectX8
Public cD3D As Direct3D8
Public cD3DHLP As D3DX8
Public cD3DDev As Direct3DDevice8

Public tDisplay As D3DDISPLAYMODE
Public tConfig As D3DPRESENT_PARAMETERS

' Camera matrix
Public sngCameraAngle As Single
Public tMatProjection As D3DMATRIX
Public tMatView As D3DMATRIX

' Effect engine
Public cCore() As clsFire
Public lngNumber As Long

' Grid
Private cGTEX As Direct3DTexture8
Private cBumpMapText As Direct3DTexture8
Private Type tpVertex
  vPosition As D3DVECTOR
  vNormal As D3DVECTOR
  vColor As Long
  U1 As Single
  V1 As Single
  U2 As Single
  V2 As Single
End Type

Private Const lngGridSize As Long = 31
Private Const sngGridBlockSize As Single = 3
Private Const lngShader As Long = D3DFVF_XYZ Or D3DFVF_NORMAL Or D3DFVF_DIFFUSE Or D3DFVF_TEX2
Private tGridData() As tpVertex
Private cGridBuffer As Direct3DVertexBuffer8
Private lngGridVertexLen As Long
Private tGridMat As D3DMATERIAL8
Private lngW As Long
Private lngX As Single
Private lngY As Single
Private lngZ As Single

Public bNormalMap As Boolean
Public bGCh As Boolean
Public bGTexture As Boolean

Private lngIndex As Long

Private Sub Main()
  bOK = False
  ' Load configuration window
  Load frmStartup
End Sub

Public Sub Initialize()
  'error handle
  On Error GoTo Failed
  'load main window
  Load frmOutput
  If frmStartup.cmbResolution.ListIndex = 3 Then frmOutput.WindowState = 2: DoEvents
  'initialize package system
  sngCamCurrentDistance = 250
  sngCamFinalDistance = 250
  sngCamCurrentHeight = 0
  sngCamFinalHeight = 0
  Set cPKG = New clsPackage
  Set cVirtualFile = New clsBinaryFile

  If Not cPKG.pkOpen(App.Path & "\SceneData.PKG") Then
    MsgBox "Master package file can not be loaded." & vbCrLf & App.Path & "\SceneData.PKG", vbCritical + vbOKOnly, "Error"
    Shutdown
  End If
  ' Initialize DirectX
  Set cDX = New DirectX8
  Set DSX = New clsSound
  DSX.devInitialize cDX, frmSetup.hWnd
  DSX.smBuffer 5
  DSX.smCreate 1, "sound\fire.buf", cPKG
  DSX.smCreate 2, "sound\troch.buf", cPKG
  DSX.smCreate 3, "sound\troch.buf", cPKG
  DSX.smCreate 4, "sound\loading.buf", cPKG
  DSX.smCreate 5, "sound\troch.buf", cPKG
  DSX.smRepeatEnable 1
  DSX.smRepeatEnable 2
  DSX.smRepeatEnable 3
  DSX.smRepeatEnable 5
  DSX.smVolume 3, -1000
  DSX.smVolume 5, -500
  Set cD3D = cDX.Direct3DCreate
  Set cD3DHLP = New D3DX8
  'get display info
  cD3D.GetAdapterDisplayMode D3DADAPTER_DEFAULT, tDisplay
  'configure 3d device
  With tConfig
    .BackBufferCount = 1                      '1 backbuffer
    .BackBufferFormat = tDisplay.Format       'current display color depth
    .BackBufferHeight = frmOutput.ScaleHeight 'window height
    .BackBufferWidth = frmOutput.ScaleWidth   'window width
    .EnableAutoDepthStencil = 1               'enable stencil
    .hDeviceWindow = frmOutput.hWnd           'link to the form
    .Windowed = 1                             'in window
    If Not cD3D.CheckDeviceType(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, .BackBufferFormat, .BackBufferFormat, .Windowed) = 0 Then
      MsgBox "Hardware acceleration not available. Can not run this demo.", vbCritical + vbOKOnly, "Error"
      Shutdown
    End If
    If bSafeMode Then
      'tested on GEFORCE 2 (with 32mb)
      .AutoDepthStencilFormat = D3DFMT_D16        '16-bit stencil (for old video adapters)
      .SwapEffect = D3DSWAPEFFECT_FLIP            'fastest
      .MultiSampleType = D3DMULTISAMPLE_NONE      'no antialiasing
      'caps check
      If Not cD3D.CheckDepthStencilMatch(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, .BackBufferFormat, .BackBufferFormat, .AutoDepthStencilFormat) = 0 Then
        MsgBox "16-Bit Stencil not supported. This demo will not run.", vbCritical + vbOKOnly, "Error"
        Shutdown
      End If
    Else
      ' Tested on RADEON X800 (with 256mb)
      .AutoDepthStencilFormat = D3DFMT_D24X8      '24-bit stencil
      .SwapEffect = D3DSWAPEFFECT_DISCARD         'for antialiasing
      .MultiSampleType = D3DMULTISAMPLE_4_SAMPLES 'x4 antialiasing
      'caps check
      If Not cD3D.CheckDepthStencilMatch(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, .BackBufferFormat, .BackBufferFormat, .AutoDepthStencilFormat) = 0 Then
        MsgBox "24-Bit Stencil not supported. Try running this demo in SafeMode.", vbCritical + vbOKOnly, "Error"
        Shutdown
      End If
      If Not cD3D.CheckDeviceMultiSampleType(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, .BackBufferFormat, .BackBufferFormat, .MultiSampleType) = 0 Then
        MsgBox "4x Antialiasing not supported. Try running this demo in SafeMode.", vbCritical + vbOKOnly, "Error"
        Shutdown
      End If
    End If
  End With
  'create 3d device
  If bSafeMode Then
    'software processing (for old video adapters)
    Set cD3DDev = cD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, tConfig.hDeviceWindow, D3DCREATE_SOFTWARE_VERTEXPROCESSING, tConfig)
  Else
    'hardware processing
    Set cD3DDev = cD3D.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, tConfig.hDeviceWindow, D3DCREATE_HARDWARE_VERTEXPROCESSING, tConfig)
  End If
  'set camera projection
  D3DXMatrixPerspectiveFovLH tMatProjection, 1, tConfig.BackBufferHeight / tConfig.BackBufferWidth, 1, 1000
  cD3DDev.SetTransform D3DTS_PROJECTION, tMatProjection
 
    
  ' Grid texture
        ReDim texRaw(0) As Byte
        If Not cPKG.pkExtract("texture\grid\default.dds", texRaw()) Then
          Set cGTEX = Nothing
          MsgBox "File can not be found in package. Unable to create binary stream." & vbCrLf & cPKG.pkNameHandle & " > " & "texture\grid\default.dds", vbExclamation + vbOKOnly, "Warning"
        Else
          Set cGTEX = cD3DHLP.CreateTextureFromFileInMemoryEx(cD3DDev, texRaw(0), UBound(texRaw()) + 1, 1024, 1024, 0, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, D3DX_FILTER_LINEAR, D3DX_FILTER_LINEAR, 0, ByVal 0, ByVal 0)
        End If
        Erase texRaw()
        ReDim texRaw(0) As Byte
        If Not cPKG.pkExtract("texture\grid\normal.dds", texRaw()) Then
          Set cBumpMapText = Nothing
          MsgBox "File can not be found in package. Unable to create binary stream." & vbCrLf & cPKG.pkNameHandle & " > " & "texture\grid\normal.dds", vbExclamation + vbOKOnly, "Warning"
        Else
          Set cBumpMapText = cD3DHLP.CreateTextureFromFileInMemoryEx(cD3DDev, texRaw(0), UBound(texRaw()) + 1, 1024, 1024, 0, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, D3DX_FILTER_LINEAR, D3DX_FILTER_LINEAR, 0, ByVal 0, ByVal 0)
        End If
        Erase texRaw()

  DOgrid
 
  'load first scene
  ReDim cCore(0)
  frmSetup.cmbEnv.ListIndex = 0
  'start rendering
  sngCameraAngle = Timer
  Randomize Timer
  RenderScene
  Load frmSetup
  frmOutput.tmrRender.Enabled = True
  bOK = True
  'error handler
  Exit Sub
Failed:
  If Not bSafeMode Then
    MsgBox "Engine: Initialization Failed." & vbCrLf & "Try running this demo in SafeMode.", vbCritical + vbOKOnly, "Error"
  Else
    MsgBox "Engine: Initialization Failed.", vbCritical + vbOKOnly, "Error"
  End If
  Shutdown
End Sub

'render scene
Public Sub RenderScene()
  'error handle
  On Error GoTo Failed
  'count fps
  lngFPS = lngFPS + 1
  'update camera
  sngCameraAngle = sngCameraAngle + 0.01
  'calculate next effect frame
  For lngNumber = 0 To UBound(cCore()) Step 1
    'set layer rotation angles
    cCore(lngNumber).sngPitch = -VectorAngle(sngCamCurrentDistance * Sin(sngCameraAngle), sngCamCurrentHeight + 50, sngCamCurrentDistance * Cos(sngCameraAngle), sngCamCurrentDistance * Sin(sngCameraAngle), 0, sngCamCurrentDistance * Cos(sngCameraAngle))
    cCore(lngNumber).sngAngle = sngCameraAngle
    'process next frame
    cCore(lngNumber).Process
  Next lngNumber
  'set camera position & look at
  If sngCamCurrentDistance > sngCamFinalDistance Then sngCamCurrentDistance = sngCamCurrentDistance - Abs(sngCamFinalDistance - sngCamCurrentDistance) / 50
  If sngCamCurrentDistance < sngCamFinalDistance Then sngCamCurrentDistance = sngCamCurrentDistance + Abs(sngCamFinalDistance - sngCamCurrentDistance) / 50
  If sngCamCurrentHeight > sngCamFinalHeight Then sngCamCurrentHeight = sngCamCurrentHeight - Abs(sngCamFinalHeight - sngCamCurrentHeight) / 50
  If sngCamCurrentHeight < sngCamFinalHeight Then sngCamCurrentHeight = sngCamCurrentHeight + Abs(sngCamFinalHeight - sngCamCurrentHeight) / 50
  D3DXMatrixLookAtLH tMatView, Vector(sngCamCurrentDistance * Sin(sngCameraAngle), sngCamCurrentHeight + 50, sngCamCurrentDistance * Cos(sngCameraAngle)), Vector(0, sngCamCurrentHeight + 0, 0), Vector(0, 1, 0)
  'render scene frame
  With cD3DDev
    .SetTransform D3DTS_VIEW, tMatView
    'clear backbuffer
    .Clear 0, ByVal 0, D3DCLEAR_TARGET Or D3DCLEAR_ZBUFFER, &HFF000000, 1, 0
    'render scene
    .BeginScene
    .SetRenderState D3DRS_ALPHABLENDENABLE, 0
    'rendering options
    If bShade Then
      .SetRenderState D3DRS_SHADEMODE, D3DSHADE_GOURAUD
    Else
      .SetRenderState D3DRS_SHADEMODE, D3DSHADE_FLAT
    End If
    If bReflections Then
      .SetRenderState D3DRS_SPECULARENABLE, 1
      .SetRenderState D3DRS_LOCALVIEWER, 1
    Else
      .SetRenderState D3DRS_SPECULARENABLE, 0
      .SetRenderState D3DRS_LOCALVIEWER, 0
    End If
    If bLighting Then
      .SetRenderState D3DRS_LIGHTING, 1
    Else
      .SetRenderState D3DRS_LIGHTING, 0
    End If
    'render grid
    If bRenderGrid Then
      If bWiregrid Then
        .SetRenderState D3DRS_FILLMODE, 2
      Else
        .SetRenderState D3DRS_FILLMODE, 3
      End If
      'grid material setup
      With tGridMat
        .diffuse.A = 1
        .diffuse.R = 1
        .diffuse.G = 1
        .diffuse.B = 1
        .emissive.A = 0.015
        .emissive.R = 0.015
        .emissive.G = 0.015
        .emissive.B = 0.015
        .specular.R = 0.4
        .specular.G = 0.3
        .specular.B = 0.2
        .power = 100
      End With
      If bGTexture Then
        If bNormalMap Then
          .SetTexture 0, cBumpMapText
          .SetTexture 1, cGTEX
        Else
          .SetTexture 0, cGTEX
        End If
      Else
        .SetTexture 0, Nothing
        .SetTexture 1, Nothing
      End If
      .SetVertexShader lngShader
      .SetStreamSource 0, cGridBuffer, lngGridVertexLen
      .SetMaterial tGridMat
      .SetRenderState D3DRS_CULLMODE, D3DCULL_CW
      'BUMP MAPPING 4 GRID (NORMAL MAP)
      If bNormalMap Then
        Dim Factor As Long
        Factor = VectorToRGBA(0.3 + Sin(sngCameraAngle) * 0.7, 1, 0.2 + Abs(Cos(sngCameraAngle)) * 0.8, 0)
        .SetRenderState D3DRS_TEXTUREFACTOR, Factor
        .SetTextureStageState 0, D3DTSS_COLORARG1, D3DTA_TEXTURE
        .SetTextureStageState 0, D3DTSS_COLOROP, D3DTOP_DOTPRODUCT3
        .SetTextureStageState 0, D3DTSS_COLORARG2, D3DTA_TFACTOR
        .SetTextureStageState 1, D3DTSS_COLOROP, D3DTOP_MODULATE
        .SetTextureStageState 1, D3DTSS_COLORARG1, D3DTA_CURRENT
        .SetTextureStageState 1, D3DTSS_COLORARG2, D3DTA_TEXTURE
        .DrawPrimitive D3DPT_TRIANGLELIST, 0, (UBound(tGridData()) + 1) / 3
        .SetTextureStageState 0, D3DTSS_COLORARG1, D3DTA_TEXTURE
        .SetTextureStageState 0, D3DTSS_COLOROP, D3DTOP_DOTPRODUCT3
        .SetTextureStageState 0, D3DTSS_COLORARG2, D3DTA_TFACTOR
      End If
      .DrawPrimitive D3DPT_TRIANGLELIST, 0, (UBound(tGridData()) + 1) / 3
      'disable dot-product 3 (default texturing)
      .SetTexture 0, Nothing
      .SetTexture 1, Nothing
      .SetTextureStageState 0, D3DTSS_COLORARG1, D3DTA_TEXTURE
      .SetTextureStageState 0, D3DTSS_COLOROP, D3DTOP_MODULATE
      .SetTextureStageState 0, D3DTSS_COLORARG2, D3DTA_CURRENT
      .SetTextureStageState 1, D3DTSS_COLORARG1, D3DTA_TEXTURE
      .SetTextureStageState 1, D3DTSS_COLOROP, D3DTOP_MODULATE
      .SetTextureStageState 1, D3DTSS_COLORARG2, D3DTA_CURRENT
    End If
    If bWireframe Then
      .SetRenderState D3DRS_FILLMODE, 2
    Else
      .SetRenderState D3DRS_FILLMODE, 3
    End If
    'Render All Static Objects
    If bRenderStatic Then
      For lngIndex = 0 To UBound(tObjectList()) Step 1
        'Render Object
        If InStr(1, tObjectList(lngIndex).id, "[ALPHA]", vbTextCompare) > 0 Then
          If frmSetup.cmbEnv.ListIndex = 2 Then
            For lngNumber = 0 To UBound(cCore()) Step 1
              cCore(lngNumber).Render
            Next lngNumber
          End If
          'need alpha blending for this object?
          If bAlphaBlend Then
            .SetRenderState D3DRS_ALPHABLENDENABLE, 1
            .SetRenderState D3DRS_DESTBLEND, D3DBLEND_DESTALPHA
            .SetRenderState D3DRS_SRCBLEND, D3DBLEND_SRCCOLOR
          End If
        End If
        'Apply Texture
        If bTexture Then
          .SetTexture 0, tObjectList(tObjectList(lngIndex).material_reference).texture_buffer
        Else
          .SetTexture 0, Nothing
        End If
        'Setup Material
        With tStMat
          .diffuse.R = tObjectList(lngIndex).emissive.R
          .diffuse.G = tObjectList(lngIndex).emissive.G
          .diffuse.B = tObjectList(lngIndex).emissive.B
          .specular.R = 0.4
          .specular.G = 0.3
          .specular.B = 0.2
          .emissive.R = 0.5
          .emissive.G = 0.5
          .emissive.B = 0.5
          .power = 100
        End With
        'Select Source Stream
        .SetRenderState D3DRS_CULLMODE, D3DCULL_NONE
        .SetMaterial tStMat
        .SetVertexShader lngStaticShader
        .SetStreamSource 0, tObjectList(lngIndex).vertex_buffer, lngStVLen
        .DrawPrimitive D3DPT_TRIANGLELIST, 0, (UBound(tObjectList(lngIndex).vertex_stream()) + 1) / 3
        .SetRenderState D3DRS_ALPHABLENDENABLE, 0
      Next lngIndex
    End If
    'render effect
    For lngNumber = 0 To UBound(cCore()) Step 1
      cCore(lngNumber).Render
    Next lngNumber
    .EndScene
    'test cooperative level
    If Not .TestCooperativeLevel = 0 Then
      MsgBox "Cooperative level lost. Can not swap buffers.", vbCritical + vbOKOnly, "Error"
      Shutdown
    Else
      'swap buffers
      .Present ByVal 0, ByVal 0, 0, ByVal 0
    End If
  End With
  'error handler
  Exit Sub
Failed:
  MsgBox "Failed to render scene.", vbCritical + vbOKOnly, "Error"
  Shutdown
End Sub

Public Sub Shutdown()
  'ignore errors (force shutdown)
  On Error Resume Next
  'disable rendering
  bOK = False
  frmOutput.tmrRender.Enabled = False
  'release package
  cPKG.pkClose
  Set cPKG = Nothing
  cVirtualFile.vfClose
  Set cVirtualFile = Nothing
  'destory grid
  Erase tGridData()
  Set cGridBuffer = Nothing
  'destroy effect engine
  Dim count As Long
  count = UBound(cCore())
  For lngNumber = 0 To count Step 1
    cCore(lngNumber).Release
    Set cCore(lngNumber) = Nothing
    frmOutput.Caption = lngNumber
  Next lngNumber
  Erase cCore()
  ' Kill sound sustem
  DSX.devRelease
  Set DSX = Nothing
  ' Destroy core objects
  Set cD3DDev = Nothing
  Set cD3DHLP = Nothing
  Set cD3D = Nothing
  Set cDX = Nothing
  'unload all forms, if loaded
  Unload frmStartup
  Unload frmSetup
  Unload frmOutput
  'finish
  End
End Sub

Private Function Vector(X As Single, Y As Single, Z As Single) As D3DVECTOR
  With Vector
    .X = X
    .Y = Y
    .Z = Z
  End With
End Function

' Creates vertex for grid
Private Function MakeVertex(X As Single, Y As Single, Z As Single, color As Long, Optional U As Single, Optional V As Single) As tpVertex
  With MakeVertex
    .vPosition = Vector(X - sngGridBlockSize * lngGridSize / 2, Y, Z - sngGridBlockSize * lngGridSize / 2)
    .vNormal = Vector(0, 1, 0)
    .vColor = color
    .U1 = U
    .V1 = V
    .U2 = U
    .V2 = V
  End With
End Function

Public Function ProcessVertex(V As tVertex, vsx As Single, vsy As Single, vsz As Single, vmx As Single, vmy As Single, vmz As Single) As tVertex
  ProcessVertex = V
  With ProcessVertex
    .Position.X = .Position.X * vsx + vmx
    .Position.Y = .Position.Y * vsy + vmy
    .Position.Z = .Position.Z * vsz + vmz
    .color = &HFFFFFFFF
  End With
End Function

' Get angle between two vectors
Public Function VectorAngle(X1 As Single, Y1 As Single, Z1 As Single, X2 As Single, Y2 As Single, Z2 As Single) As Single
  If X1 ^ 2 + Y1 ^ 2 + Z1 ^ 2 = 0 Or X2 ^ 2 + Y2 ^ 2 + Z2 ^ 2 = 0 Then
    VectorAngle = 0
  Else
    VectorAngle = ArcCos((X1 * X2 + Y1 * Y2 + Z1 * Z2) / (Sqr(X1 ^ 2 + Y1 ^ 2 + Z1 ^ 2) * Sqr(X2 ^ 2 + Y2 ^ 2 + Z2 ^ 2)))
  End If
End Function

Public Function ArcCos(Value As Single) As Single
  If Abs(Value) < 1 Then
     ArcCos = Atn(-Value / Sqr(-Value * Value + 1)) + 1.5707963267949
  ElseIf Value = 1 Then
     ArcCos = 0
  ElseIf Value = -1 Then
    ArcCos = 3.14159265358979
  End If
End Function

Public Sub DOgrid()
  'create grid
  ReDim tGridData(lngGridSize * lngGridSize * 6)
  lngZ = 0
  lngW = 0
  For lngY = 0 To lngGridSize - 1 Step 1
    For lngX = 0 To lngGridSize - 1 Step 1
      If bGCh Then
        'switch cell color
        If lngW = &HFF505050 Then
          lngW = &HFF808080
        Else
          lngW = &HFF505050
        End If
      Else
        lngW = &HFFFFFFFF
      End If
      Dim GU As Single
      Dim GV As Single
      Dim GS As Single
      GS = 1 / lngGridSize
      GU = GS * lngX
      GV = GS * lngY
      'create cell
      tGridData(lngZ + 0) = MakeVertex(lngX * sngGridBlockSize, 0, lngY * sngGridBlockSize, lngW, GU, GV)
      tGridData(lngZ + 1) = MakeVertex(lngX * sngGridBlockSize + sngGridBlockSize, 0, lngY * sngGridBlockSize, lngW, GU + GS, GV)
      tGridData(lngZ + 2) = MakeVertex(lngX * sngGridBlockSize, 0, lngY * sngGridBlockSize + sngGridBlockSize, lngW, GU, GV + GS)
      tGridData(lngZ + 3) = MakeVertex(lngX * sngGridBlockSize + sngGridBlockSize, 0, lngY * sngGridBlockSize, lngW, GU + GS, GV)
      tGridData(lngZ + 4) = MakeVertex(lngX * sngGridBlockSize + sngGridBlockSize, 0, lngY * sngGridBlockSize + sngGridBlockSize, lngW, GU + GS, GV + GS)
      tGridData(lngZ + 5) = MakeVertex(lngX * sngGridBlockSize, 0, lngY * sngGridBlockSize + sngGridBlockSize, lngW, GU, GV + GS)
      'move cursor
      lngZ = lngZ + 6
    Next lngX
  Next lngY
  'create grid's vertex buffer
  lngGridVertexLen = Len(tGridData(0))
  Set cGridBuffer = cD3DDev.CreateVertexBuffer(lngGridVertexLen * (UBound(tGridData()) + 1), 0, lngShader, D3DPOOL_DEFAULT)
  D3DVertexBuffer8SetData cGridBuffer, 0, lngGridVertexLen * (UBound(tGridData()) + 1), 0, tGridData(0)
End Sub

Private Function VectorToRGBA(X As Single, Y As Single, Z As Single, fHeight As Single) As Long
    Dim R As Integer, G As Integer, B As Integer, A As Integer
    R = 127 * X + 128
    G = 127 * Y + 128
    B = 127 * Z + 128
    A = 255 * fHeight
    VectorToRGBA = D3DColorARGB(A, R, G, B)
End Function

