import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { AvisoConexion } from './shared/offline/aviso-conexion';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, AvisoConexion],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {}
