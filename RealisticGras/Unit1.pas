{*******************************************************************************
  Yutani Render Gras Demo Form v0.2
********************************************************************************
  Simple VCL form that drives the Yutani.Render.Gras GPU grass engine.

  Sample setup (what the user asked for): a 20x20 ground patch centred on
  the origin with 1,000,000 grass blades, swaying in a fake wind that
  also slightly shifts the green color as blades bend over.

  All engine parameters are exposed through this form so you can see how
  to drive the engine from outside:
    - Field position (origin X / Y / Z) and field size (width, depth)
    - Blade height and blade width
    - Wind direction (X / Z), wind strength, wind gust frequency
    - Grass base color and tip color (color pickers)
    - Per-blade color variation
    - HDR multiplier
  Every slider pushes its value live into the running GPU engine - no
  restart, no buffer regeneration. The compute shader picks up the new
  uniforms on the next dispatch.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit Unit1;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  raylib, uGrasEngine;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    FEngine: TGrasEngine;
    pnlControls: TPanel;
    pnlRender:   TPanel;
    btnStart:       TButton;
    btnReset:       TButton;
    btnAutoRotate:  TButton;
    { Blade pool size (density) - up top because it's a global setting }
    lblBladeCount:  TLabel;
    cbBladeCount:  TComboBox;
    { Field }
    lblFieldOrigin:  TLabel;
    edtOriginX:      TEdit;
    edtOriginY:      TEdit;
    edtOriginZ:      TEdit;
    lblFieldSize:    TLabel;
    tbFieldWidth:    TTrackBar;
    lblFieldWidth:   TLabel;
    tbFieldDepth:    TTrackBar;
    lblFieldDepth:   TLabel;
    { Blade }
    lblBladeHeight:  TLabel;
    tbBladeHeight:   TTrackBar;
    lblBladeWidth:   TLabel;
    tbBladeWidth:    TTrackBar;
    { Wind }
    lblWindStrength: TLabel;
    tbWindStrength:  TTrackBar;
    lblWindAngle:    TLabel;
    tbWindAngle:     TTrackBar;
    lblWindGust:     TLabel;
    tbWindGust:      TTrackBar;
    { Bend (how soft / bendy the blades are) }
    lblBend:         TLabel;
    tbBend:          TTrackBar;
    { Mouse Push (radius + strength of the grass-parting effect when the
      user holds the left mouse button inside the Raylib window) }
    lblPushRadius:   TLabel;
    tbPushRadius:    TTrackBar;
    lblPushStrength: TLabel;
    tbPushStrength:  TTrackBar;
    { Colors }
    lblBaseColor:    TLabel;
    btnBaseColor:    TButton;
    lblBaseSwatch:   TLabel;
    lblTipColor:     TLabel;
    btnTipColor:     TButton;
    lblTipSwatch:    TLabel;
    lblColorVar:     TLabel;
    tbColorVar:      TTrackBar;
    lblHDR:          TLabel;
    tbHDR:           TTrackBar;
    { Status }
    lblFPS:      TLabel;
    lblBlades:   TLabel;
    FPSTimer: TTimer;
    FBaseColorR, FBaseColorG, FBaseColorB: Byte;
    FTipColorR,  FTipColorG,  FTipColorB:  Byte;
    ColorDlg: TColorDialog;
    function  VclColorFromRGB(R, G, B: Byte): Integer;
    procedure RGBFromVclColor(C: Integer; out R, G, B: Byte);
    procedure OnStartClick(Sender: TObject);
    procedure OnResetClick(Sender: TObject);
    procedure OnAutoRotateClick(Sender: TObject);
    procedure OnBladeCountChange(Sender: TObject);
    procedure OnFieldWidthChange(Sender: TObject);
    procedure OnFieldDepthChange(Sender: TObject);
    procedure OnOriginEditExit(Sender: TObject);
    procedure OnBladeHeightChange(Sender: TObject);
    procedure OnBladeWidthChange(Sender: TObject);
    procedure OnWindStrengthChange(Sender: TObject);
    procedure OnWindAngleChange(Sender: TObject);
    procedure OnWindGustChange(Sender: TObject);
    procedure OnBendChange(Sender: TObject);
    procedure OnPushRadiusChange(Sender: TObject);
    procedure OnPushStrengthChange(Sender: TObject);
    procedure OnBaseColorClick(Sender: TObject);
    procedure OnTipColorClick(Sender: TObject);
    procedure OnColorVarChange(Sender: TObject);
    procedure OnHDRChange(Sender: TObject);
    procedure OnFPSTimer(Sender: TObject);
    procedure PushFieldOrigin;
    procedure PushGrassColors;
    procedure PushWindAngle;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

const
  PANEL_W = 290;
  CTRL_X  = 12;
  CTRL_W  = 266;
  BTN_H   = 26;
  LBL_H   = 14;
  TB_H    = 26;

  // Vertical layout of the controls panel.
  Y_START         =   8;
  Y_RESET         =  40;
  Y_AUTOROT       =  72;
  Y_BLADE_COUNT_LBL = 104;   // Blade pool size label
  Y_BLADE_COUNT_CB  = 120;   // Blade pool size combo
  Y_FIELD_ORIGIN  = 158;     // +50 offset for the new combo
  Y_ORIGIN_EDT    = 174;
  Y_FIELD_SIZE    = 204;
  Y_FIELD_WIDTH_LBL = 220;
  Y_FIELD_WIDTH_TB  = 236;
  Y_FIELD_DEPTH_LBL = 266;
  Y_FIELD_DEPTH_TB  = 282;
  Y_BLADE_HEIGHT_LBL = 314;
  Y_BLADE_HEIGHT_TB  = 330;
  Y_BLADE_WIDTH_LBL = 360;
  Y_BLADE_WIDTH_TB  = 376;
  Y_WIND_STRENGTH_LBL = 410;
  Y_WIND_STRENGTH_TB  = 426;
  Y_WIND_ANGLE_LBL = 456;
  Y_WIND_ANGLE_TB  = 472;
  Y_WIND_GUST_LBL  = 502;
  Y_WIND_GUST_TB   = 518;
  Y_BEND_LBL         = 552;
  Y_BEND_TB          = 568;
  Y_PUSH_RADIUS_LBL  = 602;
  Y_PUSH_RADIUS_TB   = 618;
  Y_PUSH_STR_LBL     = 646;
  Y_PUSH_STR_TB      = 662;
  Y_BASE_COLOR_LBL   = 696;
  Y_BASE_COLOR_BTN   = 712;
  Y_TIP_COLOR_LBL    = 746;
  Y_TIP_COLOR_BTN   = 762;
  Y_COLOR_VAR_LBL    = 796;
  Y_COLOR_VAR_TB     = 812;
  Y_HDR_LBL          = 842;
  Y_HDR_TB           = 858;
  Y_FPS              = 894;
  Y_BLADES           = 914;

{ TForm1 - helpers }

function TForm1.VclColorFromRGB(R, G, B: Byte): Integer;
begin
  Result := (Cardinal(B) shl 16) or (Cardinal(G) shl 8) or Cardinal(R);
end;

procedure TForm1.RGBFromVclColor(C: Integer; out R, G, B: Byte);
begin
  R := Cardinal(C) and $FF;
  G := (Cardinal(C) shr 8) and $FF;
  B := (Cardinal(C) shr 16) and $FF;
end;

{ TForm1 - form setup }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Yutani Render Gras - grass field sample (20x20)';
  Self.DoubleBuffered := True;
  Self.OnResize := FormResize;
  Self.BorderStyle := bsSizeable;
  Width := 1380; Height := 970;  // +50 over 920: new Blade Count combo at the top

  // Default grass colors: dark forest green base, brighter yellow-green tip.
  FBaseColorR :=  34; FBaseColorG :=  87; FBaseColorB :=  20;
  FTipColorR  := 115; FTipColorG  := 178; FTipColorB  :=  51;

  pnlRender := TPanel.Create(Self);
  pnlRender.Parent := Self;
  pnlRender.Align := alClient;
  pnlRender.BevelOuter := bvNone;
  pnlRender.Caption := '';

  pnlControls := TPanel.Create(Self);
  pnlControls.Parent := Self;
  pnlControls.Align := alLeft;
  pnlControls.Width := PANEL_W;
  pnlControls.BevelOuter := bvRaised;
  pnlControls.Caption := '';
  pnlControls.DoubleBuffered := True;

  // ===== Top buttons =====
  btnStart := TButton.Create(Self);
  btnStart.Parent := pnlControls;
  btnStart.Caption := 'Start Engine';
  btnStart.SetBounds(CTRL_X, Y_START, CTRL_W, BTN_H);
  btnStart.OnClick := OnStartClick;

  btnReset := TButton.Create(Self);
  btnReset.Parent := pnlControls;
  btnReset.Caption := 'Reset to Defaults';
  btnReset.SetBounds(CTRL_X, Y_RESET, CTRL_W, BTN_H);
  btnReset.OnClick := OnResetClick;

  btnAutoRotate := TButton.Create(Self);
  btnAutoRotate.Parent := pnlControls;
  btnAutoRotate.Caption := 'Auto-Rotate: ON';
  btnAutoRotate.SetBounds(CTRL_X, Y_AUTOROT, CTRL_W, BTN_H);
  btnAutoRotate.OnClick := OnAutoRotateClick;

  // ===== Blade pool size (density) =====
  // Up top because it's a global setting - changing it recreates the whole
  // grass engine on the worker thread. 500K is dense enough on a 20x20 patch
  // and fluid on iGPUs; the user can pick higher values for screenshots or
  // lower values for slow laptops.
  lblBladeCount := TLabel.Create(Self);
  lblBladeCount.Parent := pnlControls;
  lblBladeCount.Caption := 'Blade Count (density):';
  lblBladeCount.SetBounds(CTRL_X, Y_BLADE_COUNT_LBL, CTRL_W, LBL_H);
  lblBladeCount.Font.Size := 9;

  cbBladeCount := TComboBox.Create(Self);
  cbBladeCount.Parent := pnlControls;
  cbBladeCount.Style := csDropDownList;
  cbBladeCount.Items.Add('250.000');
  cbBladeCount.Items.Add('500.000');
  cbBladeCount.Items.Add('1.000.000');
  cbBladeCount.Items.Add('2.000.000');
  cbBladeCount.ItemIndex := 1;  // 500K default - matches the engine's starting count
  cbBladeCount.SetBounds(CTRL_X, Y_BLADE_COUNT_CB, CTRL_W, 24);
  cbBladeCount.OnChange := OnBladeCountChange;

  // ===== Field origin =====
  lblFieldOrigin := TLabel.Create(Self);
  lblFieldOrigin.Parent := pnlControls;
  lblFieldOrigin.Caption := 'Field Origin (X, Y, Z):';
  lblFieldOrigin.SetBounds(CTRL_X, Y_FIELD_ORIGIN, CTRL_W, LBL_H);
  lblFieldOrigin.Font.Size := 9;

  edtOriginX := TEdit.Create(Self);
  edtOriginX.Parent := pnlControls;
  edtOriginX.Text := '-10.0';
  edtOriginX.SetBounds(CTRL_X,        Y_ORIGIN_EDT, 80, 22);
  edtOriginX.OnExit := OnOriginEditExit;

  edtOriginY := TEdit.Create(Self);
  edtOriginY.Parent := pnlControls;
  edtOriginY.Text := '0.0';
  edtOriginY.SetBounds(CTRL_X + 90,  Y_ORIGIN_EDT, 80, 22);
  edtOriginY.OnExit := OnOriginEditExit;

  edtOriginZ := TEdit.Create(Self);
  edtOriginZ.Parent := pnlControls;
  edtOriginZ.Text := '-10.0';
  edtOriginZ.SetBounds(CTRL_X + 180, Y_ORIGIN_EDT, 80, 22);
  edtOriginZ.OnExit := OnOriginEditExit;

  // ===== Field size =====
  lblFieldSize := TLabel.Create(Self);
  lblFieldSize.Parent := pnlControls;
  lblFieldSize.Caption := '--- Field Size ---';
  lblFieldSize.SetBounds(CTRL_X, Y_FIELD_SIZE, CTRL_W, LBL_H);
  lblFieldSize.Font.Size := 9;

  lblFieldWidth := TLabel.Create(Self);
  lblFieldWidth.Parent := pnlControls;
  lblFieldWidth.Caption := 'Width (X): 20.0';
  lblFieldWidth.SetBounds(CTRL_X, Y_FIELD_WIDTH_LBL, CTRL_W, LBL_H);
  lblFieldWidth.Font.Size := 9;

  tbFieldWidth := TTrackBar.Create(Self);
  tbFieldWidth.Parent := pnlControls;
  tbFieldWidth.Min := 1; tbFieldWidth.Max := 60; tbFieldWidth.Position := 20;
  tbFieldWidth.SetBounds(CTRL_X, Y_FIELD_WIDTH_TB, CTRL_W, TB_H);
  tbFieldWidth.TickMarks := tmBottomRight;
  tbFieldWidth.OnChange := OnFieldWidthChange;

  lblFieldDepth := TLabel.Create(Self);
  lblFieldDepth.Parent := pnlControls;
  lblFieldDepth.Caption := 'Depth (Z): 20.0';
  lblFieldDepth.SetBounds(CTRL_X, Y_FIELD_DEPTH_LBL, CTRL_W, LBL_H);
  lblFieldDepth.Font.Size := 9;

  tbFieldDepth := TTrackBar.Create(Self);
  tbFieldDepth.Parent := pnlControls;
  tbFieldDepth.Min := 1; tbFieldDepth.Max := 60; tbFieldDepth.Position := 20;
  tbFieldDepth.SetBounds(CTRL_X, Y_FIELD_DEPTH_TB, CTRL_W, TB_H);
  tbFieldDepth.TickMarks := tmBottomRight;
  tbFieldDepth.OnChange := OnFieldDepthChange;

  // ===== Blade size =====
  // Field Height (Y) is grouped here with Width/Depth conceptually - the
  // field is a 3D volume (X width, Y height, Z depth). The Y value is the
  // height the blades grow to. "Blade Width" below is the thickness of a
  // single blade (separate from the field volume).
  lblBladeHeight := TLabel.Create(Self);
  lblBladeHeight.Parent := pnlControls;
  lblBladeHeight.Caption := 'Field Height (Y): 2.00';
  lblBladeHeight.SetBounds(CTRL_X, Y_BLADE_HEIGHT_LBL, CTRL_W, LBL_H);
  lblBladeHeight.Font.Size := 9;

  tbBladeHeight := TTrackBar.Create(Self);
  tbBladeHeight.Parent := pnlControls;
  tbBladeHeight.Min := 5; tbBladeHeight.Max := 500; tbBladeHeight.Position := 200;
  tbBladeHeight.SetBounds(CTRL_X, Y_BLADE_HEIGHT_TB, CTRL_W, TB_H);
  tbBladeHeight.TickMarks := tmBottomRight;
  tbBladeHeight.OnChange := OnBladeHeightChange;

  lblBladeWidth := TLabel.Create(Self);
  lblBladeWidth.Parent := pnlControls;
  lblBladeWidth.Caption := 'Blade Width: 0.060';
  lblBladeWidth.SetBounds(CTRL_X, Y_BLADE_WIDTH_LBL, CTRL_W, LBL_H);
  lblBladeWidth.Font.Size := 9;

  tbBladeWidth := TTrackBar.Create(Self);
  tbBladeWidth.Parent := pnlControls;
  // 1..500 / 1000 = 0.001..0.5 blade width. Default 60 (= 0.06m) - thinner
  // than the previous 120 (0.12m) so blades look like grass, not chunky cards.
  tbBladeWidth.Min := 1; tbBladeWidth.Max := 500; tbBladeWidth.Position := 60;
  tbBladeWidth.SetBounds(CTRL_X, Y_BLADE_WIDTH_TB, CTRL_W, TB_H);
  tbBladeWidth.TickMarks := tmBottomRight;
  tbBladeWidth.OnChange := OnBladeWidthChange;

  // ===== Wind =====
  lblWindStrength := TLabel.Create(Self);
  lblWindStrength.Parent := pnlControls;
  lblWindStrength.Caption := 'Wind Strength: 1.00';
  lblWindStrength.SetBounds(CTRL_X, Y_WIND_STRENGTH_LBL, CTRL_W, LBL_H);
  lblWindStrength.Font.Size := 9;

  tbWindStrength := TTrackBar.Create(Self);
  tbWindStrength.Parent := pnlControls;
  tbWindStrength.Min := 0; tbWindStrength.Max := 400; tbWindStrength.Position := 150;
  tbWindStrength.SetBounds(CTRL_X, Y_WIND_STRENGTH_TB, CTRL_W, TB_H);
  tbWindStrength.TickMarks := tmBottomRight;
  tbWindStrength.OnChange := OnWindStrengthChange;

  lblWindAngle := TLabel.Create(Self);
  lblWindAngle.Parent := pnlControls;
  lblWindAngle.Caption := 'Wind Angle: 78 deg';
  lblWindAngle.SetBounds(CTRL_X, Y_WIND_ANGLE_LBL, CTRL_W, LBL_H);
  lblWindAngle.Font.Size := 9;

  tbWindAngle := TTrackBar.Create(Self);
  tbWindAngle.Parent := pnlControls;
  tbWindAngle.Min := 0; tbWindAngle.Max := 359; tbWindAngle.Position := 78;
  tbWindAngle.SetBounds(CTRL_X, Y_WIND_ANGLE_TB, CTRL_W, TB_H);
  tbWindAngle.TickMarks := tmBottomRight;
  tbWindAngle.OnChange := OnWindAngleChange;

  lblWindGust := TLabel.Create(Self);
  lblWindGust.Parent := pnlControls;
  lblWindGust.Caption := 'Wind Gust Freq: 0.60';
  lblWindGust.SetBounds(CTRL_X, Y_WIND_GUST_LBL, CTRL_W, LBL_H);
  lblWindGust.Font.Size := 9;

  tbWindGust := TTrackBar.Create(Self);
  tbWindGust.Parent := pnlControls;
  tbWindGust.Min := 1; tbWindGust.Max := 300; tbWindGust.Position := 100;
  tbWindGust.SetBounds(CTRL_X, Y_WIND_GUST_TB, CTRL_W, TB_H);
  tbWindGust.TickMarks := tmBottomRight;
  tbWindGust.OnChange := OnWindGustChange;

  // ===== Bend (how soft / bendy the blades are) =====
  // 0 = rigid (blades stand straight up regardless of wind), 1 = very soft
  // (blades bend strongly in the wind, tip displaced up to 60% of blade height).
  // Default 0.70 gives a clearly bendy look without blades lying flat.
  lblBend := TLabel.Create(Self);
  lblBend.Parent := pnlControls;
  lblBend.Caption := 'Bend Amount: 0.70';
  lblBend.SetBounds(CTRL_X, Y_BEND_LBL, CTRL_W, LBL_H);
  lblBend.Font.Size := 9;

  tbBend := TTrackBar.Create(Self);
  tbBend.Parent := pnlControls;
  tbBend.Min := 0; tbBend.Max := 100; tbBend.Position := 70;
  tbBend.SetBounds(CTRL_X, Y_BEND_TB, CTRL_W, TB_H);
  tbBend.TickMarks := tmBottomRight;
  tbBend.OnChange := OnBendChange;

  // ===== Mouse Push (radius + strength of the grass-parting effect) =====
  // When the user holds the left mouse button inside the Raylib window,
  // the wrapper computes the world hit-point on the ground plane and
  // pushes grass away from it. These two sliders tune how big the pushed
  // circle is and how strongly the blades are bent away.
  lblPushRadius := TLabel.Create(Self);
  lblPushRadius.Parent := pnlControls;
  lblPushRadius.Caption := 'Push Radius: 2.20';
  lblPushRadius.SetBounds(CTRL_X, Y_PUSH_RADIUS_LBL, CTRL_W, LBL_H);
  lblPushRadius.Font.Size := 9;

  // TrackBar 50..600 / 100 = 0.50..6.00 push radius. Default 220 = 2.20.
  tbPushRadius := TTrackBar.Create(Self);
  tbPushRadius.Parent := pnlControls;
  tbPushRadius.Min := 50; tbPushRadius.Max := 600; tbPushRadius.Position := 220;
  tbPushRadius.SetBounds(CTRL_X, Y_PUSH_RADIUS_TB, CTRL_W, TB_H);
  tbPushRadius.TickMarks := tmBottomRight;
  tbPushRadius.OnChange := OnPushRadiusChange;

  lblPushStrength := TLabel.Create(Self);
  lblPushStrength.Parent := pnlControls;
  lblPushStrength.Caption := 'Push Strength: 2.50';
  lblPushStrength.SetBounds(CTRL_X, Y_PUSH_STR_LBL, CTRL_W, LBL_H);
  lblPushStrength.Font.Size := 9;

  // TrackBar 0..500 / 100 = 0.00..5.00 push strength. Default 250 = 2.50.
  tbPushStrength := TTrackBar.Create(Self);
  tbPushStrength.Parent := pnlControls;
  tbPushStrength.Min := 0; tbPushStrength.Max := 500; tbPushStrength.Position := 250;
  tbPushStrength.SetBounds(CTRL_X, Y_PUSH_STR_TB, CTRL_W, TB_H);
  tbPushStrength.TickMarks := tmBottomRight;
  tbPushStrength.OnChange := OnPushStrengthChange;

  // ===== Colors =====
  lblBaseColor := TLabel.Create(Self);
  lblBaseColor.Parent := pnlControls;
  lblBaseColor.Caption := 'Grass Base Color (root):';
  lblBaseColor.SetBounds(CTRL_X, Y_BASE_COLOR_LBL, CTRL_W, LBL_H);
  lblBaseColor.Font.Size := 9;

  btnBaseColor := TButton.Create(Self);
  btnBaseColor.Parent := pnlControls;
  btnBaseColor.Caption := 'Pick Base Color';
  btnBaseColor.SetBounds(CTRL_X, Y_BASE_COLOR_BTN, 190, BTN_H);
  btnBaseColor.OnClick := OnBaseColorClick;

  lblBaseSwatch := TLabel.Create(Self);
  lblBaseSwatch.Parent := pnlControls;
  lblBaseSwatch.Caption := '';
  lblBaseSwatch.SetBounds(CTRL_X + 200, Y_BASE_COLOR_BTN, 60, BTN_H);
  lblBaseSwatch.Color := VclColorFromRGB(FBaseColorR, FBaseColorG, FBaseColorB);
  lblBaseSwatch.Transparent := False;

  lblTipColor := TLabel.Create(Self);
  lblTipColor.Parent := pnlControls;
  lblTipColor.Caption := 'Grass Tip Color (top):';
  lblTipColor.SetBounds(CTRL_X, Y_TIP_COLOR_LBL, CTRL_W, LBL_H);
  lblTipColor.Font.Size := 9;

  btnTipColor := TButton.Create(Self);
  btnTipColor.Parent := pnlControls;
  btnTipColor.Caption := 'Pick Tip Color';
  btnTipColor.SetBounds(CTRL_X, Y_TIP_COLOR_BTN, 190, BTN_H);
  btnTipColor.OnClick := OnTipColorClick;

  lblTipSwatch := TLabel.Create(Self);
  lblTipSwatch.Parent := pnlControls;
  lblTipSwatch.Caption := '';
  lblTipSwatch.SetBounds(CTRL_X + 200, Y_TIP_COLOR_BTN, 60, BTN_H);
  lblTipSwatch.Color := VclColorFromRGB(FTipColorR, FTipColorG, FTipColorB);
  lblTipSwatch.Transparent := False;

  lblColorVar := TLabel.Create(Self);
  lblColorVar.Parent := pnlControls;
  lblColorVar.Caption := 'Color Variation: 0.20';
  lblColorVar.SetBounds(CTRL_X, Y_COLOR_VAR_LBL, CTRL_W, LBL_H);
  lblColorVar.Font.Size := 9;

  tbColorVar := TTrackBar.Create(Self);
  tbColorVar.Parent := pnlControls;
  tbColorVar.Min := 0; tbColorVar.Max := 100; tbColorVar.Position := 20;
  tbColorVar.SetBounds(CTRL_X, Y_COLOR_VAR_TB, CTRL_W, TB_H);
  tbColorVar.TickMarks := tmBottomRight;
  tbColorVar.OnChange := OnColorVarChange;

  lblHDR := TLabel.Create(Self);
  lblHDR.Parent := pnlControls;
  lblHDR.Caption := 'HDR Multiplier: 1.00';
  lblHDR.SetBounds(CTRL_X, Y_HDR_LBL, CTRL_W, LBL_H);
  lblHDR.Font.Size := 9;

  tbHDR := TTrackBar.Create(Self);
  tbHDR.Parent := pnlControls;
  tbHDR.Min := 50; tbHDR.Max := 300; tbHDR.Position := 100;
  tbHDR.SetBounds(CTRL_X, Y_HDR_TB, CTRL_W, TB_H);
  tbHDR.TickMarks := tmBottomRight;
  tbHDR.OnChange := OnHDRChange;

  // ===== Status =====
  lblFPS := TLabel.Create(Self);
  lblFPS.Parent := pnlControls;
  lblFPS.Caption := 'FPS: 0';
  lblFPS.SetBounds(CTRL_X, Y_FPS, CTRL_W, 20);
  lblFPS.Font.Size := 10;

  lblBlades := TLabel.Create(Self);
  lblBlades.Parent := pnlControls;
  lblBlades.Caption := 'Blades: 0';
  lblBlades.SetBounds(CTRL_X, Y_BLADES, CTRL_W, 20);
  lblBlades.Font.Size := 10;

  FPSTimer := TTimer.Create(Self);
  FPSTimer.Interval := 500;
  FPSTimer.OnTimer := OnFPSTimer;
  FPSTimer.Enabled := True;

  ColorDlg := TColorDialog.Create(Self);

  // Create the grass engine: 1,000,000 blades, child of the render panel.
  // Default 500K blades - dense enough on a 20x20 patch and fluid on
  // integrated GPUs (Ryzen 4500U / Vega 6). The form's Blade Count combo
  // lets the user switch to 250K / 1M / 2M at runtime.
  FEngine := TGrasEngine.Create(pnlRender.Handle, 500000);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
  PushFieldOrigin;
  FEngine.SetFieldSize(tbFieldWidth.Position, tbFieldDepth.Position);
  FEngine.SetBladeHeight(tbBladeHeight.Position / 100.0);
  FEngine.SetBladeWidth(tbBladeWidth.Position / 1000.0);
  FEngine.SetWindStrength(tbWindStrength.Position / 100.0);
  PushWindAngle;
  FEngine.SetWindGustFreq(tbWindGust.Position / 100.0);
  PushGrassColors;
  FEngine.SetColorVariation(tbColorVar.Position / 100.0);
  FEngine.SetHDRMultiplier(tbHDR.Position / 100.0);
  FEngine.SetBendAmount(tbBend.Position / 100.0);
  FEngine.SetPushRadius(tbPushRadius.Position / 100.0);
  FEngine.SetPushStrength(tbPushStrength.Position / 100.0);
  // Auto-start the engine so the user sees a live, wind-blown grass
  // field the moment the form opens - no need to click "Start Engine"
  // manually. Without this, FActive stays False, the compute shader
  // never runs, the positions SSBO stays at (0,0,0) and every blade
  // renders as a flat triangle from its base point to the world origin.
  FEngine.StartEngine;
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  if Assigned(FEngine) and Assigned(pnlRender) then
    FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FEngine) then begin
    FEngine.StopEngine;
    FEngine.Terminate;
    FEngine.WaitFor;
    FEngine.Free;
  end;
end;

{ ============================================================================
  Helpers - push current form state into the live engine
  ============================================================================ }

procedure TForm1.PushFieldOrigin;
var
  OX, OY, OZ: Single;
  function ParseS(const S: string; Def: Single): Single;
  var C: Integer; Normed: string;
  begin
    Normed := StringReplace(Trim(S), ',', '.', [rfReplaceAll]);
    Val(Normed, Result, C);
    if C <> 0 then Result := Def;
  end;
begin
  OX := ParseS(edtOriginX.Text, -10.0);
  OY := ParseS(edtOriginY.Text,   0.0);
  OZ := ParseS(edtOriginZ.Text, -10.0);
  if Assigned(FEngine) then
    FEngine.SetFieldOrigin(OX, OY, OZ);
end;

procedure TForm1.PushGrassColors;
begin
  if Assigned(FEngine) then
    FEngine.SetGrassColors(
      FBaseColorR / 255.0, FBaseColorG / 255.0, FBaseColorB / 255.0,
      FTipColorR  / 255.0, FTipColorG  / 255.0, FTipColorB  / 255.0);
end;

procedure TForm1.PushWindAngle;
var
  AngRad: Single;
  Wx, Wz: Single;
begin
  AngRad := tbWindAngle.Position * Pi / 180.0;
  Wx := Cos(AngRad);
  Wz := Sin(AngRad);
  if Assigned(FEngine) then
    FEngine.SetWindDir(Wx, 0.0, Wz);
end;

{ ============================================================================
  Event handlers
  ============================================================================ }

procedure TForm1.OnStartClick(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.StartEngine;
end;

procedure TForm1.OnResetClick(Sender: TObject);
begin
  // Reset the engine-side state...
  if Assigned(FEngine) then FEngine.Reset;
  // ...and restore the UI controls to the defaults so they match the engine.
  edtOriginX.Text := '-10.0';
  edtOriginY.Text := '0.0';
  edtOriginZ.Text := '-10.0';
  tbFieldWidth.Position := 20;
  tbFieldDepth.Position := 20;
  tbBladeHeight.Position := 200;
  tbBladeWidth.Position  := 60;
  tbWindStrength.Position := 150;
  tbWindAngle.Position := 78;
  tbWindGust.Position := 100;
  tbBend.Position := 70;
  tbPushRadius.Position := 220;
  tbPushStrength.Position := 250;
  cbBladeCount.ItemIndex := 1;  // 500K default
  FBaseColorR :=  34; FBaseColorG :=  87; FBaseColorB :=  20;
  FTipColorR  := 115; FTipColorG  := 178; FTipColorB  :=  51;
  lblBaseSwatch.Color := VclColorFromRGB(FBaseColorR, FBaseColorG, FBaseColorB);
  lblTipSwatch.Color  := VclColorFromRGB(FTipColorR,  FTipColorG,  FTipColorB);
  tbColorVar.Position := 20;
  tbHDR.Position := 100;
  // Trigger the OnChange handlers so labels and live engine are updated.
  OnFieldWidthChange(tbFieldWidth);
  OnFieldDepthChange(tbFieldDepth);
  OnBladeHeightChange(tbBladeHeight);
  OnBladeWidthChange(tbBladeWidth);
  OnWindStrengthChange(tbWindStrength);
  OnWindAngleChange(tbWindAngle);
  OnWindGustChange(tbWindGust);
  OnBendChange(tbBend);
  OnPushRadiusChange(tbPushRadius);
  OnPushStrengthChange(tbPushStrength);
  OnColorVarChange(tbColorVar);
  OnHDRChange(tbHDR);
  PushFieldOrigin;
  PushGrassColors;
end;

procedure TForm1.OnAutoRotateClick(Sender: TObject);
begin
  if Assigned(FEngine) then
  begin
    FEngine.AutoRotate := not FEngine.AutoRotate;
    if FEngine.AutoRotate then
      btnAutoRotate.Caption := 'Auto-Rotate: ON'
    else
      btnAutoRotate.Caption := 'Auto-Rotate: OFF (use mouse mb)';
  end;
end;

procedure TForm1.OnBladeCountChange(Sender: TObject);
{ Maps the combo's index to a blade count and asks the wrapper to recreate
  the engine on the worker thread. 0=250K, 1=500K (default), 2=1M, 3=2M.
  The wrapper's RecreateEngine sets a flag that the worker thread picks up
  at the top of its next frame - it frees the old engine, creates the new
  one with the new count, calls Initialise, and pushes all current
  parameter values. The thread is never killed, so no Raylib-window flash. }
const
  BladeCounts: array[0..3] of Integer = (250000, 500000, 1000000, 2000000);
var
  Idx, NewCount: Integer;
begin
  if not Assigned(FEngine) then Exit;
  Idx := cbBladeCount.ItemIndex;
  if (Idx < 0) or (Idx > High(BladeCounts)) then Exit;
  NewCount := BladeCounts[Idx];
  FEngine.RecreateEngine(NewCount);
end;

procedure TForm1.OnFieldWidthChange(Sender: TObject);
begin
  lblFieldWidth.Caption := Format('Width (X): %.1f', [tbFieldWidth.Position * 1.0]);
  if Assigned(FEngine) then
    FEngine.SetFieldSize(tbFieldWidth.Position, tbFieldDepth.Position);
end;

procedure TForm1.OnFieldDepthChange(Sender: TObject);
begin
  lblFieldDepth.Caption := Format('Depth (Z): %.1f', [tbFieldDepth.Position * 1.0]);
  if Assigned(FEngine) then
    FEngine.SetFieldSize(tbFieldWidth.Position, tbFieldDepth.Position);
end;

procedure TForm1.OnOriginEditExit(Sender: TObject);
begin
  PushFieldOrigin;
end;

procedure TForm1.OnBladeHeightChange(Sender: TObject);
var H: Single;
begin
  H := tbBladeHeight.Position / 100.0;
  lblBladeHeight.Caption := Format('Field Height (Y): %.2f', [H]);
  if Assigned(FEngine) then
    FEngine.SetBladeHeight(H);
end;

procedure TForm1.OnBladeWidthChange(Sender: TObject);
var W: Single;
begin
  W := tbBladeWidth.Position / 1000.0;
  lblBladeWidth.Caption := Format('Blade Width: %.3f', [W]);
  if Assigned(FEngine) then
    FEngine.SetBladeWidth(W);
end;

procedure TForm1.OnWindStrengthChange(Sender: TObject);
var S: Single;
begin
  S := tbWindStrength.Position / 100.0;
  lblWindStrength.Caption := Format('Wind Strength: %.2f', [S]);
  if Assigned(FEngine) then
    FEngine.SetWindStrength(S);
end;

procedure TForm1.OnWindAngleChange(Sender: TObject);
begin
  lblWindAngle.Caption := Format('Wind Angle: %d deg', [tbWindAngle.Position]);
  PushWindAngle;
end;

procedure TForm1.OnWindGustChange(Sender: TObject);
var F: Single;
begin
  F := tbWindGust.Position / 100.0;
  lblWindGust.Caption := Format('Wind Gust Freq: %.2f', [F]);
  if Assigned(FEngine) then
    FEngine.SetWindGustFreq(F);
end;

procedure TForm1.OnBendChange(Sender: TObject);
var B: Single;
begin
  // 0..1 - 0 = rigid (blades stand upright regardless of wind),
  // 1 = very soft (tip displaced up to 60% of blade height in wind).
  B := tbBend.Position / 100.0;
  lblBend.Caption := Format('Bend Amount: %.2f', [B]);
  if Assigned(FEngine) then
    FEngine.SetBendAmount(B);
end;

procedure TForm1.OnPushRadiusChange(Sender: TObject);
var R: Single;
begin
  // Push radius in world units (0.50..6.00). Determines the size of the
  // grass-parting circle when the user holds the left mouse button.
  R := tbPushRadius.Position / 100.0;
  lblPushRadius.Caption := Format('Push Radius: %.2f', [R]);
  if Assigned(FEngine) then
    FEngine.SetPushRadius(R);
end;

procedure TForm1.OnPushStrengthChange(Sender: TObject);
var S: Single;
begin
  // Push strength (0.00..5.00). 0 = no visible effect, 5 = blades
  // almost completely flattened under the cursor.
  S := tbPushStrength.Position / 100.0;
  lblPushStrength.Caption := Format('Push Strength: %.2f', [S]);
  if Assigned(FEngine) then
    FEngine.SetPushStrength(S);
end;

procedure TForm1.OnBaseColorClick(Sender: TObject);
var R, G, B: Byte;
begin
  ColorDlg.Color := VclColorFromRGB(FBaseColorR, FBaseColorG, FBaseColorB);
  if ColorDlg.Execute then
  begin
    RGBFromVclColor(ColorDlg.Color, R, G, B);
    FBaseColorR := R; FBaseColorG := G; FBaseColorB := B;
    lblBaseSwatch.Color := VclColorFromRGB(R, G, B);
    PushGrassColors;
  end;
end;

procedure TForm1.OnTipColorClick(Sender: TObject);
var R, G, B: Byte;
begin
  ColorDlg.Color := VclColorFromRGB(FTipColorR, FTipColorG, FTipColorB);
  if ColorDlg.Execute then
  begin
    RGBFromVclColor(ColorDlg.Color, R, G, B);
    FTipColorR := R; FTipColorG := G; FTipColorB := B;
    lblTipSwatch.Color := VclColorFromRGB(R, G, B);
    PushGrassColors;
  end;
end;

procedure TForm1.OnColorVarChange(Sender: TObject);
var V: Single;
begin
  V := tbColorVar.Position / 100.0;
  lblColorVar.Caption := Format('Color Variation: %.2f', [V]);
  if Assigned(FEngine) then
    FEngine.SetColorVariation(V);
end;

procedure TForm1.OnHDRChange(Sender: TObject);
var M: Single;
begin
  M := tbHDR.Position / 100.0;
  lblHDR.Caption := Format('HDR Multiplier: %.2f', [M]);
  if Assigned(FEngine) then
    FEngine.SetHDRMultiplier(M);
end;

procedure TForm1.OnFPSTimer(Sender: TObject);
begin
  if not Assigned(FEngine) then Exit;
  lblFPS.Caption := Format('FPS: %d', [FEngine.RealFPS]);
  if Assigned(FEngine.GrassEngine) then
    lblBlades.Caption := Format('Blades: %d', [FEngine.GrassEngine.NumParticles]);
end;

end.
