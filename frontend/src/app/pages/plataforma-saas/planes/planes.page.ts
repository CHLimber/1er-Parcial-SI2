import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

import { TarjetasPlanes } from '../../../shared/planes/tarjetas-planes';

/** Planes y precios del SaaS, en una pagina propia (la portada `/` muestra las mismas tarjetas). */
@Component({
  selector: 'app-planes-page',
  standalone: true,
  imports: [RouterLink, TarjetasPlanes],
  templateUrl: './planes.page.html',
  styleUrl: './planes.page.css',
})
export class PlanesPage {}
