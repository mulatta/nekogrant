let
  neko = import ./neko;
in
{
  default = neko;
  inherit neko;
}
