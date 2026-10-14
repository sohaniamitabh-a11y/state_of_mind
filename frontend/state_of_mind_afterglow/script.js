const stage = document.getElementById('stage');
const bloom = document.getElementById('bloom');
const intro = document.getElementById('intro');
const moodArea = document.getElementById('moodArea');
const skip = document.getElementById('skip');
const response = document.getElementById('response');
const responseTitle = document.getElementById('responseTitle');
const responseCopy = document.getElementById('responseCopy');
const responseMood = document.getElementById('responseMood');
const back = document.getElementById('back');
const editionText = document.getElementById('editionText');
const recommendationsContainer = document.getElementById('recommendationsContainer');

if (editionText) {
  const message = editionText.textContent;
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    editionText.textContent = '';
    [...message].forEach((character, index) => {
      window.setTimeout(() => { editionText.textContent += character; }, index * 42);
    });
  }
}

const revealAt = 23; // let the bloom take the stage before revealing the choices
let revealed = false;

function revealMoods() {
  if (revealed) return;
  revealed = true;
  stage.classList.add('ready');
  moodArea.setAttribute('aria-hidden', 'false');
}

bloom.addEventListener('timeupdate', () => {
  if (bloom.currentTime >= revealAt) revealMoods();
});

bloom.addEventListener('ended', revealMoods);

bloom.addEventListener('error', () => {
  // Keep the interface usable if a browser cannot play the local video.
  const ambient = document.querySelector('.ambient');
  if (ambient) {
    ambient.style.background = 'radial-gradient(ellipse at 50% 45%, #241624 0%, #0a080d 48%, #050407 78%)';
  }
  window.setTimeout(revealMoods, 5000);
});

skip.addEventListener('click', revealMoods);

// Map frontend button mood identifiers to the backend ALLOWED_MOODS
const MOOD_MAPPING = {
  'Happy': 'Happy/Excitement',
  'Calm': 'Calm/Serene',
  'Sad': 'Sad/Melancholy',
  'Anger': 'Anger/Rage',
  'Confusion/Anxiety': 'Confusion/Anxiety',
  'Happy/Excitement': 'Happy/Excitement',
  'Calm/Serene': 'Calm/Serene',
  'Sad/Melancholy': 'Sad/Melancholy',
  'Anger/Rage': 'Anger/Rage'
};

const moodCopy = {
  'Happy/Excitement': ['Keep a little of this light.', 'Find something that matches your good energy.'],
  'Calm/Serene': ['Stay here for a moment.', 'A softer soundtrack for the pace you want.'],
  'Sad/Melancholy': ['You don’t have to rush out of this feeling.', 'A few things to sit with you, gently.'],
  'Anger/Rage': ['Give the feeling somewhere to go.', 'Something to help you release the noise.'],
  'Confusion/Anxiety': ['You don’t have to figure everything out right now.', 'Let’s take it one small thing at a time.'],
  'Happy': ['Keep a little of this light.', 'Find something that matches your good energy.'],
  'Calm': ['Stay here for a moment.', 'A softer soundtrack for the pace you want.'],
  'Sad': ['You don’t have to rush out of this feeling.', 'A few things to sit with you, gently.'],
  'Anger': ['Give the feeling somewhere to go.', 'Something to help you release the noise.']
};

function getApiEndpoint(backendMood) {
  const query = `/get-state?mood=${encodeURIComponent(backendMood)}`;
  // Connect to Flask backend on port 5000 if served via separate dev server (e.g. Live Server on 5500) or file://
  if (window.location.protocol === 'file:' || (window.location.port && window.location.port !== '5000')) {
    return `http://127.0.0.1:5000${query}`;
  }
  return query;
}

let activeAbortController = null;
let currentMood = null;

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text ?? '';
  return div.innerHTML;
}

function formatPopularity(score, mediaType) {
  if (score === null || score === undefined) return '';
  const num = Number(score);
  if (isNaN(num)) return '';
  if (mediaType === 'music') {
    if (num >= 1000000) return `Popularity: ${(num / 1000000).toFixed(1)}M`;
    if (num >= 1000) return `Popularity: ${(num / 1000).toFixed(0)}K`;
    return `Popularity: ${num}`;
  }
  if (mediaType === 'game') {
    if (num >= 1000) return `Popularity: ${(num / 1000).toFixed(1)}K`;
    return `Popularity: ${num}`;
  }
  return `Popularity: ${num.toFixed(1)}`;
}

function getMediaBadge(mediaType) {
  switch (mediaType) {
    case 'tv':
      return { label: 'TV Series', className: 'badge-tv' };
    case 'movie':
      return { label: 'Movie', className: 'badge-movie' };
    case 'music':
      return { label: 'Music', className: 'badge-music' };
    case 'game':
      return { label: 'Game', className: 'badge-game' };
    default:
      return { label: (mediaType || '').toUpperCase(), className: 'badge-default' };
  }
}

function renderLoading() {
  if (!recommendationsContainer) return;
  recommendationsContainer.innerHTML = `
    <div class="recs-state recs-loading" aria-live="polite">
      <div class="pulse-loader" aria-hidden="true">
        <span></span><span></span><span></span>
      </div>
      <p class="state-title">Listening to your frequency...</p>
      <p class="state-desc">Selecting the best movies, music, and games for this moment.</p>
    </div>
  `;
}

function renderError(mood, error) {
  if (!recommendationsContainer) return;
  const msg = error ? escapeHtml(error.message || String(error)) : 'Could not reach State of Mind';
  recommendationsContainer.innerHTML = `
    <div class="recs-state recs-error" aria-live="assertive">
      <span class="state-icon" aria-hidden="true">⚠</span>
      <p class="state-title">Database / Server Error</p>
      <p class="state-desc" style="color:#f0c3a9;word-break:break-word;">${msg}</p>
      <p class="state-desc">Please verify your Aiven MySQL credentials in <code>.env</code> and restart <code>app.py</code>.</p>
      <button class="retry-btn" id="retryBtn">Try again <span>↻</span></button>
    </div>
  `;
  const retryBtn = document.getElementById('retryBtn');
  if (retryBtn) {
    retryBtn.addEventListener('click', () => fetchRecommendations(mood));
  }
}

function renderCategory(title, icon, items, categoryKey) {
  const hasItems = Array.isArray(items) && items.length > 0;
  
  const cardsHtml = hasItems ? items.map((item, index) => {
    const rank = String(index + 1).padStart(2, '0');
    const badge = getMediaBadge(item.media_type);
    const fitPct = Math.round((Number(item.relevance_score) || 0) * 100);
    const popText = formatPopularity(item.popularity_score, item.media_type);

    return `
      <article class="rec-card" tabindex="0">
        <div class="rec-card-top">
          <span class="rec-index">${rank}</span>
          <span class="rec-badge ${badge.className}">${badge.label}</span>
          <span class="rec-match">${fitPct}% match</span>
        </div>
        <h4 class="rec-title" title="${escapeHtml(item.title)}">${escapeHtml(item.title)}</h4>
        <div class="rec-card-bottom">
          <div class="match-track" title="${fitPct}% relevance">
            <div class="match-fill" style="width: ${fitPct}%"></div>
          </div>
          ${popText ? `<span class="rec-meta">${popText}</span>` : ''}
        </div>
      </article>
    `;
  }).join('') : `<p class="category-empty">No recommendations available for this mood yet.</p>`;

  const countText = hasItems ? `${items.length} ${items.length === 1 ? 'item' : 'items'}` : '0 items';

  return `
    <section class="rec-category" data-category="${categoryKey}">
      <div class="category-header">
        <div class="category-title-wrap">
          <span class="category-icon" aria-hidden="true">${icon}</span>
          <h3 class="category-title">${title}</h3>
        </div>
        <span class="category-count">${countText}</span>
      </div>
      <div class="cards-list">
        ${cardsHtml}
      </div>
    </section>
  `;
}

function renderRecommendations(data) {
  if (!recommendationsContainer) return;
  const moviesTv = data.movies_tv || [];
  const music = data.music || [];
  const games = data.games || [];

  const totalCount = moviesTv.length + music.length + games.length;

  if (totalCount === 0) {
    recommendationsContainer.innerHTML = `
      <div class="recs-state recs-empty">
        <span class="state-icon" aria-hidden="true">☼</span>
        <p class="state-title">No recommendations found</p>
        <p class="state-desc">We couldn't find matches for this mood right now. Try selecting another mood.</p>
      </div>
    `;
    return;
  }

  recommendationsContainer.innerHTML = `
    <div class="recommendations-grid">
      ${renderCategory('Movies & TV', '✦', moviesTv, 'movies_tv')}
      ${renderCategory('Music', '♫', music, 'music')}
      ${renderCategory('Games', '❖', games, 'games')}
    </div>
  `;
}

async function fetchRecommendations(backendMood) {
  if (activeAbortController) {
    activeAbortController.abort();
  }
  activeAbortController = new AbortController();
  const signal = activeAbortController.signal;

  renderLoading();

  const primaryUrl = getApiEndpoint(backendMood);
  try {
    let response;
    try {
      response = await fetch(primaryUrl, { signal });
    } catch (netErr) {
      // If primary relative request failed on a local dev setup, try explicit http://127.0.0.1:5000
      if (!primaryUrl.includes('127.0.0.1:5000') && !primaryUrl.includes('localhost:5000')) {
        response = await fetch(`http://127.0.0.1:5000/get-state?mood=${encodeURIComponent(backendMood)}`, { signal });
      } else {
        throw netErr;
      }
    }

    if (!response.ok) {
      let detail = '';
      try {
        const errJson = await response.json();
        detail = errJson.error || errJson.description || errJson.message || '';
      } catch (_) {
        try {
          detail = await response.text();
        } catch (_) {}
      }
      throw new Error(detail || `Server returned HTTP ${response.status}`);
    }

    const data = await response.json();
    renderRecommendations(data);
  } catch (error) {
    if (error.name === 'AbortError') return;
    console.error('Error fetching recommendations:', error);
    renderError(backendMood, error);
  }
}

document.querySelectorAll('.mood').forEach(button => {
  button.addEventListener('click', () => {
    const rawMood = button.dataset.mood;
    const backendMood = MOOD_MAPPING[rawMood] || rawMood;
    currentMood = backendMood;

    const copy = moodCopy[backendMood] || moodCopy[rawMood] || ['Make a little room for yourself.', 'A few things to meet you where you are.'];
    responseTitle.textContent = copy[0];
    responseCopy.textContent = copy[1];

    const displayName = button.dataset.displayName || button.querySelector('.mood-name')?.textContent || rawMood;
    responseMood.textContent = displayName.toUpperCase();

    stage.classList.add('selected');
    response.setAttribute('aria-hidden', 'false');
    moodArea.setAttribute('aria-hidden', 'true');

    fetchRecommendations(backendMood);
  });
});

back.addEventListener('click', () => {
  if (activeAbortController) {
    activeAbortController.abort();
  }
  stage.classList.remove('selected');
  response.setAttribute('aria-hidden', 'true');
  moodArea.setAttribute('aria-hidden', 'false');
  if (recommendationsContainer) {
    recommendationsContainer.innerHTML = '';
  }
});
