{*******************************************************************************
  Unit1 - Yutani GPU Particles Test Form
********************************************************************************
  Simple VCL test form for the new Niagara-Light engine. Each button spawns
  one of the preset emitters (fire, smoke, explosion, sparks, rain, snow,
  magic, vortex, fountain, thruster, materialize cube). A Clear button wipes
  all emitters. A slider controls the active instance count.

  The Raylib window is embedded as a child of the render panel by the
  TParticleEngine thread (see uParticleEngine.pas). All emitter presets
  are safe to call from the VCL thread - the engine locks internally.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit Unit1;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Math,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Raylib, uParticleEngine, Yutani.Render.Particles.GPU,
  Yutani.Render.ParticlePhysics;

type
  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    FEngine: TParticleEngine;
    pnlRender:   TPanel;
    pnlControls: TPanel;
    { Status }
    lblFPS:      TLabel;
    lblPool:     TLabel;
    lblEmitters: TLabel;
    FPSTimer: TTimer;
    { Pool / time / scale sliders }
    lblPoolSize:   TLabel;
    tbPoolSize:    TTrackBar;
    lblN:          TLabel;
    tbN:           TTrackBar;
    lblScale:      TLabel;
    tbScale:       TTrackBar;
    lblSpeed:      TLabel;
    tbSpeed:       TTrackBar;
    lblHDR:        TLabel;
    tbHDR:        TTrackBar;
    { Preset buttons }
    btnFire:        TButton;
    btnSmoke:       TButton;
    btnExplosion:   TButton;
    btnSparks:      TButton;
    btnRain:        TButton;
    btnSnow:        TButton;
    btnMagic:       TButton;
    btnVortex:      TButton;
    btnFountain:    TButton;
    btnThruster:    TButton;
    btnMaterialize: TButton;
    btnDemat:       TButton;
    { Global / clear }
    btnApplyGlobals: TButton;
    btnClear:        TButton;
    btnReset:        TButton;
    lblWind:         TLabel;
    edtWindX:        TEdit;
    edtWindY:        TEdit;
    edtWindZ:        TEdit;
    lblGravity:       TLabel;
    edtGravityY:     TEdit;
    procedure OnFPSTimer(Sender: TObject);
    procedure OnPoolSizeChange(Sender: TObject);
    procedure OnNChange(Sender: TObject);
    procedure OnScaleChange(Sender: TObject);
    procedure OnSpeedChange(Sender: TObject);
    procedure OnHDRChange(Sender: TObject);
    procedure OnFireClick(Sender: TObject);
    procedure OnSmokeClick(Sender: TObject);
    procedure OnExplosionClick(Sender: TObject);
    procedure OnSparksClick(Sender: TObject);
    procedure OnRainClick(Sender: TObject);
    procedure OnSnowClick(Sender: TObject);
    procedure OnMagicClick(Sender: TObject);
    procedure OnVortexClick(Sender: TObject);
    procedure OnFountainClick(Sender: TObject);
    procedure OnThrusterClick(Sender: TObject);
    procedure OnMaterializeClick(Sender: TObject);
    procedure OnDematClick(Sender: TObject);
    procedure OnApplyGlobalsClick(Sender: TObject);
    procedure OnClearClick(Sender: TObject);
    procedure OnResetClick(Sender: TObject);
    procedure OnEmitterExpired(Sender: TObject; EmitterID: Integer;
      const Emitter: TYutaniEmitterData);
    procedure RecreateEngine(NewCount: Integer);
    function TryParseFloat(const S: string; out V: Single): Boolean;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

const
  CW = 200;   // control width
  BW = 92;    // button width (2 per row)
  BH = 30;    // button height
  BG = 6;     // button gap
  ROW = BH + BG;
  COL = BW + BG;

{ ========================================================================== }
{ TForm1 }
{ ========================================================================== }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Yutani GPU Particle Emitters';
  Position := poScreenCenter;
  Width := 1280;
  Height := 800;
  Constraints.MinWidth := 1000;
  Constraints.MinHeight := 600;

  { Render panel (right side, fills remaining width) }
  pnlRender := TPanel.Create(Self);
  pnlRender.Parent := Self;
  pnlRender.Align := alClient;
  pnlRender.BevelOuter := bvNone;
  pnlRender.Caption := '';

  { Control panel (left, fixed width 230) }
  pnlControls := TPanel.Create(Self);
  pnlControls.Parent := Self;
  pnlControls.Align := alLeft;
  pnlControls.Width := 230;
  pnlControls.BevelOuter := bvRaised;
  pnlControls.Caption := '';

  { Pool size }
  lblPoolSize := TLabel.Create(Self);
  lblPoolSize.Parent := pnlControls;
  lblPoolSize.Caption := 'Pool: 500K';
  lblPoolSize.SetBounds(10, 34, 210, 14);
  tbPoolSize := TTrackBar.Create(Self);
  tbPoolSize.Parent := pnlControls;
  tbPoolSize.Min := 1;
  tbPoolSize.Max := 25000;  // 25M max
  tbPoolSize.Frequency := 250;
  tbPoolSize.Position := 500;
  tbPoolSize.SetBounds(10, 50, 210, 26);
  tbPoolSize.TickMarks := tmBottomRight;
  tbPoolSize.OnChange := OnPoolSizeChange;

  { Active particles (N x1000) }
  lblN := TLabel.Create(Self);
  lblN.Parent := pnlControls;
  lblN.Caption := 'N x1000: 100 (10%)';
  lblN.SetBounds(10, 82, 210, 14);
  tbN := TTrackBar.Create(Self);
  tbN.Parent := pnlControls;
  tbN.Min := 0;
  tbN.Max := 1000;
  tbN.Position := 100;
  tbN.SetBounds(10, 98, 210, 26);
  tbN.TickMarks := tmBottomRight;
  tbN.OnChange := OnNChange;

  { Particle scale }
  lblScale := TLabel.Create(Self);
  lblScale.Parent := pnlControls;
  lblScale.Caption := 'Scale: 1.00';
  lblScale.SetBounds(10, 130, 210, 14);
  tbScale := TTrackBar.Create(Self);
  tbScale.Parent := pnlControls;
  tbScale.Min := 0;
  tbScale.Max := 50000;
  tbScale.Position := 1000;
  tbScale.SetBounds(10, 146, 210, 26);
  tbScale.TickMarks := tmBottomRight;
  tbScale.OnChange := OnScaleChange;

  { Time speed }
  lblSpeed := TLabel.Create(Self);
  lblSpeed.Parent := pnlControls;
  lblSpeed.Caption := 'Speed: 1.00';
  lblSpeed.SetBounds(10, 178, 210, 14);
  tbSpeed := TTrackBar.Create(Self);
  tbSpeed.Parent := pnlControls;
  tbSpeed.Min := 0;
  tbSpeed.Max := 1000;
  tbSpeed.Position := 1000;
  tbSpeed.SetBounds(10, 194, 210, 26);
  tbSpeed.TickMarks := tmBottomRight;
  tbSpeed.OnChange := OnSpeedChange;

  { HDR multiplier }
  lblHDR := TLabel.Create(Self);
  lblHDR.Parent := pnlControls;
  lblHDR.Caption := 'HDR: 1.0';
  lblHDR.SetBounds(10, 226, 210, 14);
  tbHDR := TTrackBar.Create(Self);
  tbHDR.Parent := pnlControls;
  tbHDR.Min := 0;
  tbHDR.Max := 50;
  tbHDR.Position := 10;
  tbHDR.SetBounds(10, 242, 210, 26);
  tbHDR.TickMarks := tmBottomRight;
  tbHDR.OnChange := OnHDRChange;

  { Status labels }
  lblFPS := TLabel.Create(Self);
  lblFPS.Parent := pnlControls;
  lblFPS.Caption := 'FPS: 0';
  lblFPS.SetBounds(10, 274, 210, 16);
  lblFPS.Font.Size := 10;

  lblPool := TLabel.Create(Self);
  lblPool.Parent := pnlControls;
  lblPool.Caption := 'Pool: 0';
  lblPool.SetBounds(10, 290, 210, 16);
  lblPool.Font.Size := 10;

  lblEmitters := TLabel.Create(Self);
  lblEmitters.Parent := pnlControls;
  lblEmitters.Caption := 'Emitters: 0';
  lblEmitters.SetBounds(10, 306, 210, 16);
  lblEmitters.Font.Size := 10;

  { === Preset buttons === }
  btnFire := TButton.Create(Self);
  btnFire.Parent := pnlControls;
  btnFire.Caption := 'Fire';
  btnFire.SetBounds(10, 332, BW, BH);
  btnFire.OnClick := OnFireClick;

  btnSmoke := TButton.Create(Self);
  btnSmoke.Parent := pnlControls;
  btnSmoke.Caption := 'Smoke';
  btnSmoke.SetBounds(10 + COL, 332, BW, BH);
  btnSmoke.OnClick := OnSmokeClick;

  btnExplosion := TButton.Create(Self);
  btnExplosion.Parent := pnlControls;
  btnExplosion.Caption := 'Explosion';
  btnExplosion.SetBounds(10, 332 + ROW, BW, BH);
  btnExplosion.OnClick := OnExplosionClick;

  btnSparks := TButton.Create(Self);
  btnSparks.Parent := pnlControls;
  btnSparks.Caption := 'Sparks';
  btnSparks.SetBounds(10 + COL, 332 + ROW, BW, BH);
  btnSparks.OnClick := OnSparksClick;

  btnRain := TButton.Create(Self);
  btnRain.Parent := pnlControls;
  btnRain.Caption := 'Rain';
  btnRain.SetBounds(10, 332 + ROW*2, BW, BH);
  btnRain.OnClick := OnRainClick;

  btnSnow := TButton.Create(Self);
  btnSnow.Parent := pnlControls;
  btnSnow.Caption := 'Snow';
  btnSnow.SetBounds(10 + COL, 332 + ROW*2, BW, BH);
  btnSnow.OnClick := OnSnowClick;

  btnMagic := TButton.Create(Self);
  btnMagic.Parent := pnlControls;
  btnMagic.Caption := 'Magic';
  btnMagic.SetBounds(10, 332 + ROW*3, BW, BH);
  btnMagic.OnClick := OnMagicClick;

  btnVortex := TButton.Create(Self);
  btnVortex.Parent := pnlControls;
  btnVortex.Caption := 'Vortex';
  btnVortex.SetBounds(10 + COL, 332 + ROW*3, BW, BH);
  btnVortex.OnClick := OnVortexClick;

  btnFountain := TButton.Create(Self);
  btnFountain.Parent := pnlControls;
  btnFountain.Caption := 'Fountain';
  btnFountain.SetBounds(10, 332 + ROW*4, BW, BH);
  btnFountain.OnClick := OnFountainClick;

  btnThruster := TButton.Create(Self);
  btnThruster.Parent := pnlControls;
  btnThruster.Caption := 'Thruster';
  btnThruster.SetBounds(10 + COL, 332 + ROW*4, BW, BH);
  btnThruster.OnClick := OnThrusterClick;

  btnMaterialize := TButton.Create(Self);
  btnMaterialize.Parent := pnlControls;
  btnMaterialize.Caption := 'Mat. Cube';
  btnMaterialize.SetBounds(10, 332 + ROW*5, BW, BH);
  btnMaterialize.OnClick := OnMaterializeClick;

  btnDemat := TButton.Create(Self);
  btnDemat.Parent := pnlControls;
  btnDemat.Caption := 'Demat. Cube';
  btnDemat.SetBounds(10 + COL, 332 + ROW*5, BW, BH);
  btnDemat.OnClick := OnDematClick;

  { Global wind / gravity inputs }
  lblWind := TLabel.Create(Self);
  lblWind.Parent := pnlControls;
  lblWind.Caption := 'Global Wind (X,Y,Z):';
  lblWind.SetBounds(10, 332 + ROW*6, 210, 14);
  edtWindX := TEdit.Create(Self);
  edtWindX.Parent := pnlControls;
  edtWindX.Text := '0.0';
  edtWindX.SetBounds(10, 348 + ROW*6, 60, 22);
  edtWindY := TEdit.Create(Self);
  edtWindY.Parent := pnlControls;
  edtWindY.Text := '0.0';
  edtWindY.SetBounds(75, 348 + ROW*6, 60, 22);
  edtWindZ := TEdit.Create(Self);
  edtWindZ.Parent := pnlControls;
  edtWindZ.Text := '0.0';
  edtWindZ.SetBounds(140, 348 + ROW*6, 60, 22);

  lblGravity := TLabel.Create(Self);
  lblGravity.Parent := pnlControls;
  lblGravity.Caption := 'Global Gravity Y:';
  lblGravity.SetBounds(10, 374 + ROW*6, 210, 14);
  edtGravityY := TEdit.Create(Self);
  edtGravityY.Parent := pnlControls;
  edtGravityY.Text := '0.0';
  edtGravityY.SetBounds(10, 390 + ROW*6, 130, 22);

  btnApplyGlobals := TButton.Create(Self);
  btnApplyGlobals.Parent := pnlControls;
  btnApplyGlobals.Caption := 'Apply Globals';
  btnApplyGlobals.SetBounds(145, 390 + ROW*6, 80, 22);
  btnApplyGlobals.OnClick := OnApplyGlobalsClick;

  { Clear + Reset }
  btnClear := TButton.Create(Self);
  btnClear.Parent := pnlControls;
  btnClear.Caption := 'Clear All';
  btnClear.SetBounds(10, 422 + ROW*6, 100, BH);
  btnClear.OnClick := OnClearClick;

  btnReset := TButton.Create(Self);
  btnReset.Parent := pnlControls;
  btnReset.Caption := 'Reset Engine';
  btnReset.SetBounds(120, 422 + ROW*6, 100, BH);
  btnReset.OnClick := OnResetClick;

  { FPS Timer - updates the status labels every 500ms }
  FPSTimer := TTimer.Create(Self);
  FPSTimer.Interval := 500;
  FPSTimer.OnTimer := OnFPSTimer;
  FPSTimer.Enabled := True;

  { Create the engine and bind it to the render panel }
  FEngine := TParticleEngine.Create(pnlRender.Handle, tbPoolSize.Position * 1024);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
  // Wire OnEmitterExpired so the explosion preset can chain sub-emitters.
  FEngine.OnEmitterExpired := OnEmitterExpired;
  FEngine.StartEngine;
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  if Assigned(FEngine) and Assigned(pnlRender) then
    FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FEngine) then
  begin
    FEngine.StopEngine;
    FEngine.Terminate;
    FEngine.WaitFor;
    FEngine.Free;
  end;
end;

{ === Status timer === }

procedure TForm1.OnFPSTimer(Sender: TObject);
begin
  if not Assigned(FEngine) then Exit;
  lblFPS.Caption := Format('FPS: %d', [FEngine.RealFPS]);
  if Assigned(FEngine.ParticleEngine) then
  begin
    lblPool.Caption := Format('Pool: %d', [FEngine.ParticleEngine.NumParticles]);
    lblEmitters.Caption := Format('Emitters: %d', [FEngine.GetEmitterCount]);
  end;
end;

{ === Slider handlers === }

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

procedure TForm1.OnNChange(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SetInstancesX1000(tbN.Position);
  lblN.Caption := Format('N x1000: %d (%d%%)', [tbN.Position, tbN.Position div 10]);
end;

procedure TForm1.OnScaleChange(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SetParticleScale(tbScale.Position / 1000.0);
  lblScale.Caption := Format('Scale: %.2f', [tbScale.Position / 1000.0]);
end;

procedure TForm1.OnSpeedChange(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SetTimeScale(tbSpeed.Position / 1000.0);
  lblSpeed.Caption := Format('Speed: %.2f', [tbSpeed.Position / 1000.0]);
end;

procedure TForm1.OnHDRChange(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.SetHDRMultiplier(tbHDR.Position / 10.0);
  lblHDR.Caption := Format('HDR: %.1f', [tbHDR.Position / 10.0]);
end;

procedure TForm1.RecreateEngine(NewCount: Integer);
begin
  if Assigned(FEngine) then
  begin
    FEngine.StopEngine;
    FEngine.Terminate;
    FEngine.WaitFor;
    FEngine.Free;
  end;
  FEngine := TParticleEngine.Create(pnlRender.Handle, NewCount);
  FEngine.SetDimensions(pnlRender.Width, pnlRender.Height);
  FEngine.SetParticleScale(tbScale.Position / 1000.0);
  FEngine.SetTimeScale(tbSpeed.Position / 1000.0);
  FEngine.SetInstancesX1000(tbN.Position);
  FEngine.SetHDRMultiplier(tbHDR.Position / 10.0);
  FEngine.OnEmitterExpired := OnEmitterExpired;
  FEngine.StartEngine;
end;

{ === Preset button handlers ===
  Each spawns a preset emitter at a sensible location near the world origin. }

procedure TForm1.OnFireClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateFireEmitter(Vector3Create(0, 0, 0), 0.4, 3000);
end;

procedure TForm1.OnSmokeClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateSmokeEmitter(Vector3Create(-1, 0, 0), 0.4, 2000);
end;

procedure TForm1.OnExplosionClick(Sender: TObject);
begin
  if Assigned(FEngine) then
  begin
    FEngine.CreateExplosionEmitter(Vector3Create(1, 0.3, 0), 0.6, 2000);
    FEngine.CreateSmokeEmitter(Vector3Create(1, 0.3, 0), 0.5, 1500);
  end;
end;

procedure TForm1.OnSparksClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateSparksEmitter(Vector3Create(0, 0.5, 1), 0.3, 1500);
end;

procedure TForm1.OnRainClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateRainEmitter(Vector3Create(-2, 0, -2), Vector3Create(2, 4, 2), 3000);
end;

procedure TForm1.OnSnowClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateSnowEmitter(Vector3Create(-2, 0, -2), Vector3Create(2, 4, 2), 2000);
end;

procedure TForm1.OnMagicClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateMagicEmitter(Vector3Create(0, 1.0, 0), 0.7, 2000);
end;

procedure TForm1.OnVortexClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateVortexEmitter(Vector3Create(0, 0.5, 0),
      Vector3Create(0, 1, 0), 1.0, 2500);
end;

procedure TForm1.OnFountainClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateFountainEmitter(Vector3Create(0, -0.5, 0), 2000);
end;

procedure TForm1.OnThrusterClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.CreateThrusterEmitter(Vector3Create(0, 0, -1),
      Vector3Create(0, 0, 1), 0.3, 2000);
end;

procedure TForm1.OnMaterializeClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.EmitMaterializeCube(Vector3Create(0, 0, 0), 0.1);
end;

procedure TForm1.OnDematClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.EmitDematerializeCube(Vector3Create(0, 0, 0), 0.1);
end;

{ === Global wind / gravity === }

function TForm1.TryParseFloat(const S: string; out V: Single): Boolean;
var E: Integer;
begin
  Val(S, V, E);
  Result := (E = 0);
end;

procedure TForm1.OnApplyGlobalsClick(Sender: TObject);
var
  WX, WY, WZ, GY: Single;
begin
  if not Assigned(FEngine) then Exit;
  if not TryParseFloat(Trim(edtWindX.Text), WX) then WX := 0;
  if not TryParseFloat(Trim(edtWindY.Text), WY) then WY := 0;
  if not TryParseFloat(Trim(edtWindZ.Text), WZ) then WZ := 0;
  if not TryParseFloat(Trim(edtGravityY.Text), GY) then GY := 0;
  FEngine.SetGlobalWind(Vector3Create(WX, WY, WZ));
  FEngine.SetGlobalGravity(Vector3Create(0, GY, 0));
end;

procedure TForm1.OnClearClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.ClearEmitters;
end;

procedure TForm1.OnResetClick(Sender: TObject);
begin
  if Assigned(FEngine) then
    FEngine.Reset;
  tbScale.Position := 1000;
  tbSpeed.Position := 1000;
  tbHDR.Position := 10;
  tbN.Position := 100;
  edtWindX.Text := '0.0';
  edtWindY.Text := '0.0';
  edtWindZ.Text := '0.0';
  edtGravityY.Text := '0.0';
  lblScale.Caption := 'Scale: 1.00';
  lblN.Caption := 'N x1000: 100 (10%)';
  lblSpeed.Caption := 'Speed: 1.00';
  lblHDR.Caption := 'HDR: 1.0';
end;


procedure TForm1.OnEmitterExpired(Sender: TObject; EmitterID: Integer;
  const Emitter: TYutaniEmitterData);
begin
{ === Sub-emitter chain demo ===
  When a OneShotAutoRemove emitter expires, this callback fires on the engine
  thread. }

end;

end.
