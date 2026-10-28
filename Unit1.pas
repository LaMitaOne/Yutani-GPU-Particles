{*******************************************************************************
  Yutani Particle Demo Form v0.2
********************************************************************************
  Adds PageControl with two tabs:
    Tab 1 "Show Mode"  - Lorenz params (sigma/rho/beta)
    Tab 2 "Emitter"    - Color picker, size, alpha, lifetime for emitter modes

  ComboBox now has 12 show modes + 10 emitter modes (Fog, Fire, Rain, Snow,
  Smoke, Explosion, Sparks, Fountain, Storm, Dust) = 23 total.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit Unit1;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  raylib, uParticleEngine;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    FEngine: TParticleEngine;
    pnlControls: TPanel;
    pnlRender:   TPanel;
    btnStart:   TButton;
    btnRestart: TButton;
    btnReset:   TButton;
    lblMode:    TLabel;
    cbMode:     TComboBox;
    { Common controls (always visible) }
    tbPoolSize:        TTrackBar;
    tbParticlesX1000:  TTrackBar;
    tbScale:           TTrackBar;
    tbSpeed:           TTrackBar;
    lblPoolSize:        TLabel;
    lblParticlesX1000:  TLabel;
    lblScale:           TLabel;
    lblSpeed:           TLabel;
    lblFPS:       TLabel;
    lblActive:    TLabel;
    lblPoolTotal: TLabel;
    FPSTimer: TTimer;
    btnAutoRotate: TButton;
    { PageControl with 2 tabs }
    pgControl:    TPageControl;
    tsShowMode:   TTabSheet;
    tsEmitter:    TTabSheet;
    { Tab 1: Show Mode (Lorenz params) }
    lblSigma:          TLabel;
    tbSigma:           TTrackBar;
    lblRho:            TLabel;
    tbRho:             TTrackBar;
    lblBeta:           TLabel;
    tbBeta:            TTrackBar;
    { Tab 2: Emitter Settings }
    lblEmColor:        TLabel;
    btnEmColor:       TButton;
    lblEmColorSwatch:   TLabel;
    lblEmSize:         TLabel;
    tbEmSize:          TTrackBar;
    lblEmAlpha:        TLabel;
    tbEmAlpha:         TTrackBar;
    lblEmLifetime:     TLabel;
    tbEmLifetime:      TTrackBar;
    FEmColor: TColorB;
    ColorDlg: TColorDialog;
    function MakeCol(r, g, b, a: Byte): TColorB;
    function VclColorFromTColorB(const C: TColorB): Integer;
    procedure OnStartClick(Sender: TObject);
    procedure OnRestartClick(Sender: TObject);
    procedure OnResetClick(Sender: TObject);
    procedure OnModeChange(Sender: TObject);
    procedure OnPoolSizeChange(Sender: TObject);
    procedure OnParticlesX1000Change(Sender: TObject);
    procedure OnScaleChange(Sender: TObject);
    procedure OnSpeedChange(Sender: TObject);
    procedure OnSigmaChange(Sender: TObject);
    procedure OnRhoChange(Sender: TObject);
    procedure OnBetaChange(Sender: TObject);
    procedure OnEmColorClick(Sender: TObject);
    procedure OnEmSizeChange(Sender: TObject);
    procedure OnEmAlphaChange(Sender: TObject);
    procedure OnEmLifetimeChange(Sender: TObject);
    procedure OnFPSTimer(Sender: TObject);
    procedure OnAutoRotateClick(Sender: TObject);
    procedure RecreateEngine(NewCount: Integer);
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

const
  PANEL_W = 280;
  CTRL_X  = 10;
  CTRL_W  = 260;
  BTN_H   = 28;
  LBL_H   = 14;  TB_H = 28;

  Y_START     = 10;
  Y_RESTART   = 44;
  Y_RESET     = 78;
  Y_MODE_LBL  = 112;
  Y_MODE_CB   = 128;
  Y_POOL_LBL  = 162;  Y_POOL_TB   = 178;
  Y_NX1000_LBL = 224; Y_NX1000_TB = 240;
  Y_SCALE_LBL  = 286; Y_SCALE_TB  = 302;
  Y_SPEED_LBL  = 348; Y_SPEED_TB  = 364;
  Y_PGCONTROL = 398;
  PG_H        = 250;
  Y_FPS       = 654;
  Y_ACTIVE    = 674;
  Y_POOL_TOT  = 694;
  Y_AUTOROT   = 716;

  { Tab 1: Show Mode (Lorenz) - positions inside the TabSheet }
  T1_SIGMA_LBL = 10;  T1_SIGMA_TB = 26;
  T1_RHO_LBL   = 66;  T1_RHO_TB   = 82;
  T1_BETA_LBL  = 122; T1_BETA_TB  = 138;

  { Tab 2: Emitter - positions inside the TabSheet }
  T2_COLOR_LBL    = 10;
  T2_COLOR_BTN    = 26;
  T2_SIZE_LBL     = 66;
  T2_SIZE_TB      = 82;
  T2_ALPHA_LBL    = 122;
  T2_ALPHA_TB     = 138;
  T2_LIFETIME_LBL = 178;
  T2_LIFETIME_TB  = 194;

const
  { Default RGB colors for each emitter mode (modes 12-33). Index = mode-12.
    Picked to match what each effect "looks like" so the user gets a sensible
    color immediately when switching to it. }
  EmitterDefaultColors: array[0..47, 0..2] of Byte = (
    (200, 200, 200),  // 12 Fog - light gray
    (255, 100,   0),  // 13 Fire - orange
    ( 50, 100, 200),  // 14 Rain - blue
    (240, 240, 250),  // 15 Snow - white
    ( 80,  80,  80),  // 16 Smoke - dark gray
    (255, 200,  50),  // 17 Explosion - yellow-orange
    (255, 220, 100),  // 18 Sparks - yellow
    (100, 180, 255),  // 19 Fountain2 - light blue
    (120, 120, 130),  // 20 Storm - gray
    (200, 190, 170),  // 21 Dust - beige
    ( 80,  50,  20),  // 22 Ants - dark brown
    ( 15,  15,  20),  // 23 Black Goo - black
    (180, 220, 255),  // 24 Bubbles - light blue-white
    (200, 255, 100),  // 25 Fireflies - yellow-green
    (100, 150,  50),  // 26 Leaves - green
    (255, 100, 255),  // 27 Energy - magenta
    (100, 255, 255),  // 28 Plasma - cyan
    (200, 220, 255),  // 29 Lightning - white-blue
    ( 60,  60,  60),  // 30 Ash - dark gray
    (120,  80,  40),  // 31 Debris - brown
    (220, 220, 220),  // 32 Steam - white
    (240, 240, 250),  // 33 Snow Drift - white
    (100,  80,  40),  // 34 Insects - brown
    (180, 180, 180),  // 35 Swarm - light gray
    (255, 255, 255),  // 36 Beam - white
    (200, 100, 255),  // 37 Portal - magenta-purple
    (100, 220, 255),  // 38 Crystal - cyan
    (255, 240, 150),  // 39 Pixie Dust - yellow
    (200, 200, 220),  // 40 Ghost Mist - pale
    (150, 200, 255),  // 41 Comet - blue-white
    (255, 180,  80),  // 42 Shockwave - orange
    (150, 200, 255),  // 43 Rain Splash - light blue
    (255,  80,  20),  // 44 Lava Bubble - red-orange
    (255, 255, 230),  // 45 Star Field - warm white
    (150, 100, 200),  // 46 Nebula - purple
    ( 60,  60,  70),  // 47 Tornado - dark gray
    (255, 240, 180),  // 48 Glow - warm yellow
    (255, 250, 200),  // 49 Vol. Light - warm light
    (200, 180, 130),  // 50 Sandstorm - sandy
    (200, 220, 255),  // 51 Hailstorm - icy blue
    ( 50, 100, 180),  // 52 Whirlpool - deep blue
    (100, 100, 110),  // 53 Mushroom - gray
    (140, 140, 140),  // 54 Smoke Column - medium gray
    ( 20,  20,  25),  // 55 Black Smoke - very dark
    (100, 150, 255),  // 56 Engine Exhaust - blue-white
    (255, 200,  80),  // 57 Spark Trail - amber
    (150, 200, 255),  // 58 Magic Missile - blue-white
    (240, 245, 250)   // 59 Clouds - off-white
  );

function TForm1.MakeCol(r, g, b, a: Byte): TColorB;
begin
  Result.r := r; Result.g := g; Result.b := b; Result.a := a;
end;

function TForm1.VclColorFromTColorB(const C: TColorB): Integer;
begin
  Result := (Cardinal(C.b) shl 16) or (Cardinal(C.g) shl 8) or Cardinal(C.r);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Yutani GPU Particles';
  Self.DoubleBuffered := True;
  Self.OnResize := FormResize;
  Self.BorderStyle := bsSizeable;
  Width := 1400; Height :=800;

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

  // ===== Buttons =====
  btnStart := TButton.Create(Self);
  btnStart.Parent := pnlControls;
  btnStart.Caption := 'Start Engine';
  btnStart.SetBounds(CTRL_X, Y_START, CTRL_W, BTN_H);
  btnStart.OnClick := OnStartClick;

  btnRestart := TButton.Create(Self);
  btnRestart.Parent := pnlControls;
  btnRestart.Caption := 'Restart (t=0)';
  btnRestart.SetBounds(CTRL_X, Y_RESTART, CTRL_W, BTN_H);
  btnRestart.OnClick := OnRestartClick;

  btnReset := TButton.Create(Self);
  btnReset.Parent := pnlControls;
  btnReset.Caption := 'Reset All';
  btnReset.SetBounds(CTRL_X, Y_RESET, CTRL_W, BTN_H);
  btnReset.OnClick := OnResetClick;

  // ===== Mode ComboBox (23 modes) =====
  lblMode := TLabel.Create(Self);
  lblMode.Parent := pnlControls;
  lblMode.Caption := 'Effect:';
  lblMode.SetBounds(CTRL_X, Y_MODE_LBL, CTRL_W, LBL_H);
  lblMode.Font.Size := 9;

  cbMode := TComboBox.Create(Self);
  cbMode.Parent := pnlControls;
  cbMode.Style := csDropDownList;
  cbMode.Items.Add('Lorenz');
  cbMode.Items.Add('Cube');
  cbMode.Items.Add('Sphere');
  cbMode.Items.Add('Wave');
  cbMode.Items.Add('Galaxy');
  cbMode.Items.Add('Fountain');
  cbMode.Items.Add('Vortex');
  cbMode.Items.Add('DNA Helix');
  cbMode.Items.Add('Black Hole');
  cbMode.Items.Add('Explode');
  cbMode.Items.Add('Flow Field');
  cbMode.Items.Add('Stickman Scene');
  cbMode.Items.Add('Fog');
  cbMode.Items.Add('Fire');
  cbMode.Items.Add('Rain');
  cbMode.Items.Add('Snow');
  cbMode.Items.Add('Smoke');
  cbMode.Items.Add('Explosion');
  cbMode.Items.Add('Sparks');
  cbMode.Items.Add('Fountain2');
  cbMode.Items.Add('Storm');
  cbMode.Items.Add('Dust');
  cbMode.Items.Add('Ants');
  cbMode.Items.Add('Black Goo');
  cbMode.Items.Add('Bubbles');
  cbMode.Items.Add('Fireflies');
  cbMode.Items.Add('Leaves');
  cbMode.Items.Add('Energy');
  cbMode.Items.Add('Plasma');
  cbMode.Items.Add('Lightning');
  cbMode.Items.Add('Ash');
  cbMode.Items.Add('Debris');
  cbMode.Items.Add('Steam');
  cbMode.Items.Add('Snow Drift');
  cbMode.Items.Add('Insects');
  cbMode.Items.Add('Swarm');
  cbMode.Items.Add('Beam');
  cbMode.Items.Add('Portal');
  cbMode.Items.Add('Crystal');
  cbMode.Items.Add('Pixie Dust');
  cbMode.Items.Add('Ghost Mist');
  cbMode.Items.Add('Comet');
  cbMode.Items.Add('Shockwave');
  cbMode.Items.Add('Rain Splash');
  cbMode.Items.Add('Lava Bubble');
  cbMode.Items.Add('Star Field');
  cbMode.Items.Add('Nebula');
  cbMode.Items.Add('Tornado');
  cbMode.Items.Add('Glow');
  cbMode.Items.Add('Vol. Light');
  cbMode.Items.Add('Sandstorm');
  cbMode.Items.Add('Hailstorm');
  cbMode.Items.Add('Whirlpool');
  cbMode.Items.Add('Mushroom');
  cbMode.Items.Add('Smoke Column');
  cbMode.Items.Add('Black Smoke');
  cbMode.Items.Add('Engine Exhaust');
  cbMode.Items.Add('Spark Trail');
  cbMode.Items.Add('Magic Missile');
  cbMode.Items.Add('Clouds');
  cbMode.ItemIndex := 0;
  cbMode.SetBounds(CTRL_X, Y_MODE_CB, CTRL_W, 24);
  cbMode.OnChange := OnModeChange;

  // ===== Common TrackBars (above PageControl) =====
  lblPoolSize := TLabel.Create(Self);
  lblPoolSize.Parent := pnlControls;
  lblPoolSize.Caption := 'Pool: 500K';
  lblPoolSize.SetBounds(CTRL_X, Y_POOL_LBL, CTRL_W, LBL_H);
  lblPoolSize.Font.Size := 9;

  tbPoolSize := TTrackBar.Create(Self);
  tbPoolSize.Parent := pnlControls;
  tbPoolSize.Min := 1;  tbPoolSize.Max := 25000;  tbPoolSize.Position := 500;
  tbPoolSize.SetBounds(CTRL_X, Y_POOL_TB, CTRL_W, TB_H);
  tbPoolSize.TickMarks := tmBottomRight;
  tbPoolSize.OnChange := OnPoolSizeChange;

  lblParticlesX1000 := TLabel.Create(Self);
  lblParticlesX1000.Parent := pnlControls;
  lblParticlesX1000.Caption := 'N x1000: 1000 (100%)';
  lblParticlesX1000.SetBounds(CTRL_X, Y_NX1000_LBL, CTRL_W, LBL_H);
  lblParticlesX1000.Font.Size := 9;

  tbParticlesX1000 := TTrackBar.Create(Self);
  tbParticlesX1000.Parent := pnlControls;
  tbParticlesX1000.Min := 0;  tbParticlesX1000.Max := 1000;  tbParticlesX1000.Position := 1000;
  tbParticlesX1000.SetBounds(CTRL_X, Y_NX1000_TB, CTRL_W, TB_H);
  tbParticlesX1000.TickMarks := tmBottomRight;
  tbParticlesX1000.OnChange := OnParticlesX1000Change;

  lblScale := TLabel.Create(Self);
  lblScale.Parent := pnlControls;
  lblScale.Caption := 'Scale: 1.00';
  lblScale.SetBounds(CTRL_X, Y_SCALE_LBL, CTRL_W, LBL_H);
  lblScale.Font.Size := 9;

  tbScale := TTrackBar.Create(Self);
  tbScale.Parent := pnlControls;
  tbScale.Min := 0;  tbScale.Max := 5000;  tbScale.Position := 1000;
  tbScale.SetBounds(CTRL_X, Y_SCALE_TB, CTRL_W, TB_H);
  tbScale.TickMarks := tmBottomRight;
  tbScale.OnChange := OnScaleChange;

  lblSpeed := TLabel.Create(Self);
  lblSpeed.Parent := pnlControls;
  lblSpeed.Caption := 'Speed: 0.20';
  lblSpeed.SetBounds(CTRL_X, Y_SPEED_LBL, CTRL_W, LBL_H);
  lblSpeed.Font.Size := 9;

  tbSpeed := TTrackBar.Create(Self);
  tbSpeed.Parent := pnlControls;
  tbSpeed.Min := 0;  tbSpeed.Max := 1000;  tbSpeed.Position := 200;
  tbSpeed.SetBounds(CTRL_X, Y_SPEED_TB, CTRL_W, TB_H);
  tbSpeed.TickMarks := tmBottomRight;
  tbSpeed.OnChange := OnSpeedChange;

  // ===== PageControl with 2 tabs =====
  pgControl := TPageControl.Create(Self);
  pgControl.Parent := pnlControls;
  pgControl.SetBounds(CTRL_X, Y_PGCONTROL, CTRL_W, PG_H);

  tsShowMode := TTabSheet.Create(Self);
  tsShowMode.PageControl := pgControl;
  tsShowMode.Caption := 'Lorenz';

  tsEmitter := TTabSheet.Create(Self);
  tsEmitter.PageControl := pgControl;
  tsEmitter.Caption := 'Emitter';

  // --- Tab 1: Lorenz params ---
  lblSigma := TLabel.Create(Self);
  lblSigma.Parent := tsShowMode;
  lblSigma.Caption := 'Sigma: 10.0';
  lblSigma.SetBounds(10, T1_SIGMA_LBL, CTRL_W - 20, LBL_H);
  lblSigma.Font.Size := 9;

  tbSigma := TTrackBar.Create(Self);
  tbSigma.Parent := tsShowMode;
  tbSigma.Min := 0;  tbSigma.Max := 2000;  tbSigma.Position := 1000;
  tbSigma.SetBounds(10, T1_SIGMA_TB, CTRL_W - 20, TB_H);
  tbSigma.TickMarks := tmBottomRight;
  tbSigma.OnChange := OnSigmaChange;

  lblRho := TLabel.Create(Self);
  lblRho.Parent := tsShowMode;
  lblRho.Caption := 'Rho: 28.0';
  lblRho.SetBounds(10, T1_RHO_LBL, CTRL_W - 20, LBL_H);
  lblRho.Font.Size := 9;

  tbRho := TTrackBar.Create(Self);
  tbRho.Parent := tsShowMode;
  tbRho.Min := 0;  tbRho.Max := 3000;  tbRho.Position := 2800;
  tbRho.SetBounds(10, T1_RHO_TB, CTRL_W - 20, TB_H);
  tbRho.TickMarks := tmBottomRight;
  tbRho.OnChange := OnRhoChange;

  lblBeta := TLabel.Create(Self);
  lblBeta.Parent := tsShowMode;
  lblBeta.Caption := 'Beta: 2.67';
  lblBeta.SetBounds(10, T1_BETA_LBL, CTRL_W - 20, LBL_H);
  lblBeta.Font.Size := 9;

  tbBeta := TTrackBar.Create(Self);
  tbBeta.Parent := tsShowMode;
  tbBeta.Min := 0;  tbBeta.Max := 1000;  tbBeta.Position := 267;
  tbBeta.SetBounds(10, T1_BETA_TB, CTRL_W - 20, TB_H);
  tbBeta.TickMarks := tmBottomRight;
  tbBeta.OnChange := OnBetaChange;

  // --- Tab 2: Emitter settings ---
  lblEmColor := TLabel.Create(Self);
  lblEmColor.Parent := tsEmitter;
  lblEmColor.Caption := 'Color:';
  lblEmColor.SetBounds(10, T2_COLOR_LBL, CTRL_W - 20, LBL_H);
  lblEmColor.Font.Size := 9;

  btnEmColor := TButton.Create(Self);
  btnEmColor.Parent := tsEmitter;
  btnEmColor.Caption := 'Pick Color';
  btnEmColor.SetBounds(10, T2_COLOR_BTN, 180, BTN_H);
  btnEmColor.OnClick := OnEmColorClick;
  FEmColor := MakeCol(255, 140, 20, 200);

  lblEmColorSwatch := TLabel.Create(Self);
  lblEmColorSwatch.Parent := tsEmitter;
  lblEmColorSwatch.Caption := '';
  lblEmColorSwatch.SetBounds(200, T2_COLOR_BTN, 60, BTN_H);
  lblEmColorSwatch.Color := VclColorFromTColorB(FEmColor);
  lblEmColorSwatch.Transparent := False;

  ColorDlg := TColorDialog.Create(Self);

  lblEmSize := TLabel.Create(Self);
  lblEmSize.Parent := tsEmitter;
  lblEmSize.Caption := 'Size: 0.70';
  lblEmSize.SetBounds(10, T2_SIZE_LBL, CTRL_W - 20, LBL_H);
  lblEmSize.Font.Size := 9;

  tbEmSize := TTrackBar.Create(Self);
  tbEmSize.Parent := tsEmitter;
  tbEmSize.Min := 1;  tbEmSize.Max := 500;  tbEmSize.Position := 70; // 0.70 default
  tbEmSize.SetBounds(10, T2_SIZE_TB, CTRL_W - 20, TB_H);
  tbEmSize.TickMarks := tmBottomRight;
  tbEmSize.OnChange := OnEmSizeChange;

  lblEmAlpha := TLabel.Create(Self);
  lblEmAlpha.Parent := tsEmitter;
  lblEmAlpha.Caption := 'Alpha: 100';
  lblEmAlpha.SetBounds(10, T2_ALPHA_LBL, CTRL_W - 20, LBL_H);
  lblEmAlpha.Font.Size := 9;

  tbEmAlpha := TTrackBar.Create(Self);
  tbEmAlpha.Parent := tsEmitter;
  tbEmAlpha.Min := 0;  tbEmAlpha.Max := 255;  tbEmAlpha.Position := 100;
  tbEmAlpha.SetBounds(10, T2_ALPHA_TB, CTRL_W - 20, TB_H);
  tbEmAlpha.TickMarks := tmBottomRight;
  tbEmAlpha.OnChange := OnEmAlphaChange;

  lblEmLifetime := TLabel.Create(Self);
  lblEmLifetime.Parent := tsEmitter;
  lblEmLifetime.Caption := 'Lifetime: 5.0 sec';
  lblEmLifetime.SetBounds(10, T2_LIFETIME_LBL, CTRL_W - 20, LBL_H);
  lblEmLifetime.Font.Size := 9;

  tbEmLifetime := TTrackBar.Create(Self);
  tbEmLifetime.Parent := tsEmitter;
  tbEmLifetime.Min := 1;  tbEmLifetime.Max := 300;  tbEmLifetime.Position := 50;
  tbEmLifetime.SetBounds(10, T2_LIFETIME_TB, CTRL_W - 20, TB_H);
  tbEmLifetime.TickMarks := tmBottomRight;
  tbEmLifetime.OnChange := OnEmLifetimeChange;

  // ===== Status labels =====
  lblFPS := TLabel.Create(Self);
  lblFPS.Parent := pnlControls;
  lblFPS.Caption := 'FPS: 0';
  lblFPS.SetBounds(CTRL_X, Y_FPS, CTRL_W, 20);
  lblFPS.Font.Size := 10;

  lblActive := TLabel.Create(Self);
  lblActive.Parent := pnlControls;
  lblActive.Caption := 'Active: 0';
  lblActive.SetBounds(CTRL_X, Y_ACTIVE, CTRL_W, 20);
  lblActive.Font.Size := 10;

  lblPoolTotal := TLabel.Create(Self);
  lblPoolTotal.Parent := pnlControls;
  lblPoolTotal.Caption := 'Pool: 0';
  lblPoolTotal.SetBounds(CTRL_X, Y_POOL_TOT, CTRL_W, 20);
  lblPoolTotal.Font.Size := 10;

  FPSTimer := TTimer.Create(Self);
  FPSTimer.Interval := 500;
  FPSTimer.OnTimer := OnFPSTimer;
  FPSTimer.Enabled := True;

  // Auto-Rotate toggle button
  btnAutoRotate := TButton.Create(Self);
  btnAutoRotate.Parent := pnlControls;
  btnAutoRotate.Caption := 'Auto-Rotate: ON';
  btnAutoRotate.SetBounds(CTRL_X, Y_AUTOROT, CTRL_W, BTN_H);
  btnAutoRotate.OnClick := OnAutoRotateClick;

  FEngine := TParticleEngine.Create(pnlRender.Handle, tbPoolSize.Position * 1024);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
  FEngine.SetInstancesX1000(tbParticlesX1000.Position);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  if Assigned(FEngine) and Assigned(pnlRender) then
    FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FEngine) then begin
    FEngine.StopEngine; FEngine.Terminate; FEngine.WaitFor; FEngine.Free;
  end;
end;

procedure TForm1.OnStartClick(Sender: TObject);
begin if Assigned(FEngine) then FEngine.StartEngine; end;

procedure TForm1.OnRestartClick(Sender: TObject);
begin if Assigned(FEngine) then FEngine.Restart; end;

procedure TForm1.OnResetClick(Sender: TObject);
begin
  tbParticlesX1000.Position := 1000;
  tbScale.Position := 1000;  tbSpeed.Position := 200;
  tbSigma.Position := 1000;  tbRho.Position := 2800;  tbBeta.Position := 267;
  cbMode.ItemIndex := 0;
  if Assigned(FEngine) then FEngine.Reset;
end;

procedure TForm1.OnModeChange(Sender: TObject);
var
  EmIdx: Integer;
begin
  if Assigned(FEngine) then
    FEngine.SetMode(cbMode.ItemIndex);
  if cbMode.ItemIndex <= 11 then
  begin
    // Show mode - Lorenz tab
    pgControl.ActivePage := tsShowMode;
  end
  else
  begin
    // Emitter mode - switch tab + set default color for this effect
    pgControl.ActivePage := tsEmitter;
    EmIdx := cbMode.ItemIndex - 12;
    if (EmIdx >= 0) and (EmIdx <= High(EmitterDefaultColors)) then
    begin
      FEmColor.r := EmitterDefaultColors[EmIdx][0];
      FEmColor.g := EmitterDefaultColors[EmIdx][1];
      FEmColor.b := EmitterDefaultColors[EmIdx][2];
      FEmColor.a := tbEmAlpha.Position;
      lblEmColorSwatch.Color := VclColorFromTColorB(FEmColor);
    end;
    if Assigned(FEngine) then
    begin
      FEngine.SetEmColor(FEmColor.r/255.0, FEmColor.g/255.0, FEmColor.b/255.0, FEmColor.a/255.0);
      FEngine.SetEmSize(tbEmSize.Position / 100.0);
    end;
  end;
end;

procedure TForm1.OnPoolSizeChange(Sender: TObject);
var Count: Integer;
begin
  Count := tbPoolSize.Position * 1024;
  if tbPoolSize.Position < 1000 then
    lblPoolSize.Caption := Format('Pool: %dK', [tbPoolSize.Position])
  else
    lblPoolSize.Caption := Format('Pool: %.1fM', [tbPoolSize.Position / 1000.0]);
  RecreateEngine(Count);
end;

procedure TForm1.OnParticlesX1000Change(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetInstancesX1000(tbParticlesX1000.Position);
  lblParticlesX1000.Caption := Format('N x1000: %d (%d%%)', [tbParticlesX1000.Position, tbParticlesX1000.Position div 10]);
end;

procedure TForm1.OnScaleChange(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetParticleScale(tbScale.Position / 1000.0);
  lblScale.Caption := Format('Scale: %.2f', [tbScale.Position / 1000.0]);
end;

procedure TForm1.OnSpeedChange(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetTimeScale(tbSpeed.Position / 1000.0);
  lblSpeed.Caption := Format('Speed: %.2f', [tbSpeed.Position / 1000.0]);
end;

procedure TForm1.OnSigmaChange(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetSigma(tbSigma.Position / 100.0);
  lblSigma.Caption := Format('Sigma: %.1f', [tbSigma.Position / 100.0]);
end;

procedure TForm1.OnRhoChange(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetRho(tbRho.Position / 100.0);
  lblRho.Caption := Format('Rho: %.1f', [tbRho.Position / 100.0]);
end;

procedure TForm1.OnBetaChange(Sender: TObject);
begin
  if Assigned(FEngine) then FEngine.SetBeta(tbBeta.Position / 100.0);
  lblBeta.Caption := Format('Beta: %.2f', [tbBeta.Position / 100.0]);
end;

procedure TForm1.OnEmColorClick(Sender: TObject);
begin
  ColorDlg.Color := VclColorFromTColorB(FEmColor);
  if ColorDlg.Execute then
  begin
    FEmColor.r := Cardinal(ColorDlg.Color) and $FF;
    FEmColor.g := (Cardinal(ColorDlg.Color) shr 8) and $FF;
    FEmColor.b := (Cardinal(ColorDlg.Color) shr 16) and $FF;
    FEmColor.a := tbEmAlpha.Position;
    lblEmColorSwatch.Color := VclColorFromTColorB(FEmColor);
    if Assigned(FEngine) then
      FEngine.SetEmColor(FEmColor.r/255.0, FEmColor.g/255.0, FEmColor.b/255.0, FEmColor.a/255.0);
  end;
end;

procedure TForm1.OnEmSizeChange(Sender: TObject);
begin
  lblEmSize.Caption := Format('Size: %.2f', [tbEmSize.Position / 100.0]);
  if Assigned(FEngine) then
    FEngine.SetEmSize(tbEmSize.Position / 100.0);
end;

procedure TForm1.OnEmAlphaChange(Sender: TObject);
begin
  lblEmAlpha.Caption := Format('Alpha: %d', [tbEmAlpha.Position]);
  FEmColor.a := tbEmAlpha.Position;
  lblEmColorSwatch.Color := VclColorFromTColorB(FEmColor);
  if Assigned(FEngine) then
    FEngine.SetEmColor(FEmColor.r/255.0, FEmColor.g/255.0, FEmColor.b/255.0, FEmColor.a/255.0);
end;

procedure TForm1.OnEmLifetimeChange(Sender: TObject);
begin
  lblEmLifetime.Caption := Format('Lifetime: %.1f sec', [tbEmLifetime.Position / 10.0]);
end;

procedure TForm1.RecreateEngine(NewCount: Integer);
begin
  if Assigned(FEngine) then begin
    FEngine.StopEngine; FEngine.Terminate; FEngine.WaitFor; FEngine.Free;
  end;
  FEngine := TParticleEngine.Create(pnlRender.Handle, NewCount);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
  FEngine.SetParticleScale(tbScale.Position / 1000.0);
  FEngine.SetTimeScale(tbSpeed.Position / 1000.0);
  FEngine.SetSigma(tbSigma.Position / 100.0);
  FEngine.SetRho(tbRho.Position / 100.0);
  FEngine.SetBeta(tbBeta.Position / 100.0);
  FEngine.SetInstancesX1000(tbParticlesX1000.Position);
  FEngine.SetMode(cbMode.ItemIndex);
  FEngine.StartEngine;
end;

procedure TForm1.OnFPSTimer(Sender: TObject);
begin
  if not Assigned(FEngine) then Exit;
  lblFPS.Caption := Format('FPS: %d', [FEngine.RealFPS]);
  if Assigned(FEngine.ParticleEngine) then begin
    lblActive.Caption := Format('Active: %d', [FEngine.ParticleEngine.ParticleCount]);
    lblPoolTotal.Caption := Format('Pool: %d', [FEngine.ParticleEngine.NumParticles]);
  end;
end;

procedure TForm1.OnAutoRotateClick(Sender: TObject);
begin
  if Assigned(FEngine) then
  begin
    FEngine.AutoRotate := not FEngine.AutoRotate;
    if FEngine.AutoRotate then
      btnAutoRotate.Caption := 'Auto-Rotate: ON'
    else
      btnAutoRotate.Caption := 'Auto-Rotate: OFF (Arrows+MMB)';
  end;
end;

end.
