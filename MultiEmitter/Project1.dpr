program Project1;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  uParticleEngine in 'uParticleEngine.pas',
  Yutani.Render.Particles.GPU in 'Yutani.Render.Particles.GPU.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
