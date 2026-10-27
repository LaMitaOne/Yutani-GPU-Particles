{*******************************************************************************
  Yutani Particle Demo Form
********************************************************************************

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit Unit1;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls, raylib, uParticleEngine;

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
    tbPoolSize:        TTrackBar;
    tbParticlesX1000:  TTrackBar;
    tbScale:           TTrackBar;
    tbSpeed:           TTrackBar;
    tbSigma:           TTrackBar;
    tbRho:             TTrackBar;
    tbBeta:            TTrackBar;
    lblPoolSize:        TLabel;
    lblParticlesX1000:  TLabel;
    lblScale:           TLabel;
    lblSpeed:           TLabel;
    lblSigma:           TLabel;
    lblRho:             TLabel;
    lblBeta:            TLabel;
    lblFPS:       TLabel;
    lblActive:    TLabel;
    lblPoolTotal: TLabel;
    FPSTimer: TTimer;
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
    procedure OnFPSTimer(Sender: TObject);
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
  BTN_H   = 28;  BTN_GAP = 6;
  LBL_H   = 14;  TB_H = 28;  TB_GAP = 4;

  Y_START     = 10;
  Y_RESTART   = 44;
  Y_RESET     = 78;

  Y_MODE_LBL  = 112;
  Y_MODE_CB   = 128;

  Y_POOL_LBL  = 162;
  Y_POOL_TB   = 178;
  Y_NX1000_LBL = 224;  Y_NX1000_TB = 240;
  Y_SCALE_LBL  = 286;   Y_SCALE_TB  = 302;
  Y_SPEED_LBL  = 348;   Y_SPEED_TB  = 364;
  Y_SIGMA_LBL  = 410;   Y_SIGMA_TB  = 426;
  Y_RHO_LBL    = 472;   Y_RHO_TB    = 488;
  Y_BETA_LBL   = 534;   Y_BETA_TB   = 550;

  Y_FPS      = 586;
  Y_ACTIVE   = 606;
  Y_POOL_TOT = 626;
  Y_MOUSE    = 646;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Yutani GPU Particles';
  Self.DoubleBuffered := True;
  Width := 1400; Height := 750;

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

  // ===== Mode ComboBox (11 modes) =====
  lblMode := TLabel.Create(Self);
  lblMode.Parent := pnlControls;
  lblMode.Caption := 'Show Mode:';
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
  cbMode.ItemIndex := 0;
  cbMode.SetBounds(CTRL_X, Y_MODE_CB, CTRL_W, 24);
  cbMode.OnChange := OnModeChange;

  // ===== TrackBars =====
  // Pool Size: 1 to 5000 (each step = 1K particles, max 5M)
  lblPoolSize := TLabel.Create(Self);
  lblPoolSize.Parent := pnlControls;
  lblPoolSize.Caption := 'Pool: 500K';
  lblPoolSize.SetBounds(CTRL_X, Y_POOL_LBL, CTRL_W, LBL_H);
  lblPoolSize.Font.Size := 9;

  tbPoolSize := TTrackBar.Create(Self);
  tbPoolSize.Parent := pnlControls;
  tbPoolSize.Min := 1;        // 1K minimum
  tbPoolSize.Max := 25000;     // 25M maximum (5000 * 1024 = 5,120,000)
  tbPoolSize.Frequency := 250; // tick every 100K
  tbPoolSize.Position := 500;  // 500K default
  tbPoolSize.SetBounds(CTRL_X, Y_POOL_TB, CTRL_W, TB_H);
  tbPoolSize.TickMarks := tmBottomRight;
  tbPoolSize.OnChange := OnPoolSizeChange;

  // N x1000: 0 to 1000 (default 1000 = show ALL particles)
  lblParticlesX1000 := TLabel.Create(Self);
  lblParticlesX1000.Parent := pnlControls;
  lblParticlesX1000.Caption := 'N x1000: 1000 (100%)';
  lblParticlesX1000.SetBounds(CTRL_X, Y_NX1000_LBL, CTRL_W, LBL_H);
  lblParticlesX1000.Font.Size := 9;

  tbParticlesX1000 := TTrackBar.Create(Self);
  tbParticlesX1000.Parent := pnlControls;
  tbParticlesX1000.Min := 0;  tbParticlesX1000.Max := 1000;
  tbParticlesX1000.Position := 1000;  // Show ALL by default
  tbParticlesX1000.SetBounds(CTRL_X, Y_NX1000_TB, CTRL_W, TB_H);
  tbParticlesX1000.TickMarks := tmBottomRight;
  tbParticlesX1000.OnChange := OnParticlesX1000Change;

  // Scale (0..5000, x0.001)
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

  // Speed (0..1000, x0.001)
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

  // Sigma (0..2000, x0.01)
  lblSigma := TLabel.Create(Self);
  lblSigma.Parent := pnlControls;
  lblSigma.Caption := 'Sigma: 10.0';
  lblSigma.SetBounds(CTRL_X, Y_SIGMA_LBL, CTRL_W, LBL_H);
  lblSigma.Font.Size := 9;

  tbSigma := TTrackBar.Create(Self);
  tbSigma.Parent := pnlControls;
  tbSigma.Min := 0;  tbSigma.Max := 2000;  tbSigma.Position := 1000;
  tbSigma.SetBounds(CTRL_X, Y_SIGMA_TB, CTRL_W, TB_H);
  tbSigma.TickMarks := tmBottomRight;
  tbSigma.OnChange := OnSigmaChange;

  // Rho (0..3000, x0.01)
  lblRho := TLabel.Create(Self);
  lblRho.Parent := pnlControls;
  lblRho.Caption := 'Rho: 28.0';
  lblRho.SetBounds(CTRL_X, Y_RHO_LBL, CTRL_W, LBL_H);
  lblRho.Font.Size := 9;

  tbRho := TTrackBar.Create(Self);
  tbRho.Parent := pnlControls;
  tbRho.Min := 0;  tbRho.Max := 3000;  tbRho.Position := 2800;
  tbRho.SetBounds(CTRL_X, Y_RHO_TB, CTRL_W, TB_H);
  tbRho.TickMarks := tmBottomRight;
  tbRho.OnChange := OnRhoChange;

  // Beta (0..1000, x0.01)
  lblBeta := TLabel.Create(Self);
  lblBeta.Parent := pnlControls;
  lblBeta.Caption := 'Beta: 2.67';
  lblBeta.SetBounds(CTRL_X, Y_BETA_LBL, CTRL_W, LBL_H);
  lblBeta.Font.Size := 9;

  tbBeta := TTrackBar.Create(Self);
  tbBeta.Parent := pnlControls;
  tbBeta.Min := 0;  tbBeta.Max := 1000;  tbBeta.Position := 267;
  tbBeta.SetBounds(CTRL_X, Y_BETA_TB, CTRL_W, TB_H);
  tbBeta.TickMarks := tmBottomRight;
  tbBeta.OnChange := OnBetaChange;

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
  // ===== Timer =====
  FPSTimer := TTimer.Create(Self);
  FPSTimer.Interval := 500;
  FPSTimer.OnTimer := OnFPSTimer;
  FPSTimer.Enabled := True;

  // ===== Engine =====
  FEngine := TParticleEngine.Create(pnlRender.Handle, tbPoolSize.Position * 1024);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
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

// ===== Button handlers =====

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

// ===== Mode ComboBox =====

procedure TForm1.OnModeChange(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SetMode(cbMode.ItemIndex);
end;

// ===== TrackBar handlers =====

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

// ===== Engine recreation =====

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

// ===== UI timer =====

procedure TForm1.OnFPSTimer(Sender: TObject);
begin
  if not Assigned(FEngine) then Exit;
  lblFPS.Caption := Format('FPS: %d', [FEngine.RealFPS]);
  if Assigned(FEngine.ParticleEngine) then begin
    lblActive.Caption := Format('Active: %d', [FEngine.ParticleEngine.ParticleCount]);
    lblPoolTotal.Caption := Format('Pool: %d', [FEngine.ParticleEngine.NumParticles]);
  end;
end;

end.
