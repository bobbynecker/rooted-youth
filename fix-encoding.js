(() => {
  // Convert text that was accidentally saved with the wrong character encoding.
  const cp1252 = {
    0x20ac: 0x80, 0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84,
    0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88,
    0x2030: 0x89, 0x0160: 0x8a, 0x2039: 0x8b, 0x0152: 0x8c,
    0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92, 0x201c: 0x93,
    0x201d: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02dc: 0x98, 0x2122: 0x99, 0x0161: 0x9a, 0x203a: 0x9b,
    0x0153: 0x9c, 0x017e: 0x9e, 0x0178: 0x9f
  };

  const decoder = new TextDecoder('utf-8', { fatal: true });

  function repair(value) {
    if (!/[\u0080-\uffff]/.test(value)) return value;
    try {
      const byteValues = [...value].map((character) => {
        const code = character.codePointAt(0);
        return code <= 0xff ? code : cp1252[code];
      });
      if (byteValues.some((byte) => byte === undefined)) return value;
      return decoder.decode(Uint8Array.from(byteValues));
    } catch {
      return value;
    }
  }

  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const textNodes = [];
  while (walker.nextNode()) textNodes.push(walker.currentNode);
  textNodes.forEach((node) => { node.nodeValue = repair(node.nodeValue); });

  document.title = repair(document.title);
  document.querySelectorAll('[aria-label], [placeholder], [title]').forEach((element) => {
    ['aria-label', 'placeholder', 'title'].forEach((attribute) => {
      if (element.hasAttribute(attribute)) element.setAttribute(attribute, repair(element.getAttribute(attribute)));
    });
  });
  const footerDetails = document.querySelector('footer small');
  if (footerDetails && !footerDetails.querySelector('.footer-policy-link')) {
    const spacer = document.createTextNode(' | ');
    const policyLink = document.createElement('a');
    policyLink.className = 'footer-policy-link';
    policyLink.href = 'privacy.html';
    policyLink.textContent = 'Privacy Policy';
    footerDetails.append(spacer, policyLink);
  }

  const prayerNotice = document.querySelector('.prayer-privacy-note');
  if (prayerNotice && !prayerNotice.querySelector('.prayer-policy-link')) {
    const policyLine = document.createElement('p');
    const policyLink = document.createElement('a');
    policyLine.className = 'prayer-policy-link';
    policyLink.href = 'privacy.html';
    policyLink.textContent = 'Read the Rooted Privacy Policy';
    policyLine.append(policyLink);
    prayerNotice.append(policyLine);
  }
})();
