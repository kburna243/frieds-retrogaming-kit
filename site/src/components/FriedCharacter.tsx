import React, { useId, useState } from 'react';
import { playBeep, playCoinSound, playSuccess } from '../utils/retroAudio';

export type FriedExpression = 'friendly' | 'winking' | 'surprised' | 'happy' | 'neutral' | 'confused';
export type FriedPose = 'controller' | 'thumbs-up' | 'laptop' | 'celebrate' | 'pixel';

interface FriedCharacterProps {
  expression?: FriedExpression;
  pose?: FriedPose;
  size?: 'xxs' | 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl' | 'hero';
  className?: string;
  speechBubble?: string;
  interactive?: boolean;
  onExpressionChange?: (exp: FriedExpression) => void;
  showCable?: boolean;
  glow?: boolean;
  /** accessible name; without it the figure is decorative */
  label?: string;
}

export const FriedCharacter: React.FC<FriedCharacterProps> = ({
  expression = 'friendly',
  pose = 'controller',
  size = 'md',
  className = '',
  speechBubble,
  interactive = false,
  onExpressionChange,
  showCable = true,
  glow = true,
  label,
}) => {
  // unique SVG ids so several mascots on one page never share gradients/filters
  const uid = useId().replace(/:/g, '');
  const id = (n: string) => `${n}-${uid}`;
  const [currentExp, setCurrentExp] = useState<FriedExpression>(expression);
  const [isBlinking, setIsBlinking] = useState(false);
  const [wobble, setWobble] = useState(false);

  // Sync external expression change
  React.useEffect(() => {
    setCurrentExp(expression);
  }, [expression]);

  // Periodic subtle blink effect
  React.useEffect(() => {
    const interval = setInterval(() => {
      if (Math.random() > 0.4) {
        setIsBlinking(true);
        setTimeout(() => setIsBlinking(false), 160);
      }
    }, 4500);
    return () => clearInterval(interval);
  }, []);

  const handleClick = () => {
    if (!interactive) return;
    setWobble(true);
    setTimeout(() => setWobble(false), 600);

    const expressions: FriedExpression[] = ['friendly', 'winking', 'surprised', 'happy', 'neutral', 'confused'];
    const nextIdx = (expressions.indexOf(currentExp) + 1) % expressions.length;
    const nextExp = expressions[nextIdx];
    setCurrentExp(nextExp);
    if (onExpressionChange) {
      onExpressionChange(nextExp);
    }
    if (nextExp === 'happy') {
      playSuccess();
    } else if (nextExp === 'winking') {
      playCoinSound();
    } else {
      playBeep(520 + nextIdx * 40, 'sine', 0.08);
    }
  };

  const sizeDimensions = {
    xxs: { w: 24, h: 24, class: 'w-6 h-6' },
    xs: { w: 40, h: 40, class: 'w-10 h-10' },
    sm: { w: 80, h: 80, class: 'w-20 h-20' },
    md: { w: 120, h: 120, class: 'w-28 h-28 md:w-32 md:h-32' },
    lg: { w: 180, h: 180, class: 'w-40 h-40 md:w-48 md:h-48' },
    xl: { w: 240, h: 240, class: 'w-56 h-56 md:w-64 md:h-64' },
    '2xl': { w: 320, h: 320, class: 'w-72 h-72 md:w-80 md:h-80' },
    hero: { w: 380, h: 380, class: 'w-80 h-80 sm:w-96 sm:h-96 md:w-[420px] md:h-[420px]' },
  };

  const currentSize = sizeDimensions[size];

  // Render 8-Bit Pixel Mode
  if (pose === 'pixel') {
    return (
      <div className={`relative inline-flex flex-col items-center select-none ${className}`}>
        {speechBubble && (
          <div className="absolute -top-14 left-1/2 -translate-x-1/2 z-20 whitespace-nowrap bg-[#F6F2E9] text-[#0B1B23] border-2 border-[#0B1B23] px-3 py-1.5 rounded-lg shadow-lg font-mono text-xs font-bold animate-bounce">
            {speechBubble}
            <div className="absolute -bottom-2 left-1/2 -translate-x-1/2 w-0 h-0 border-l-[6px] border-l-transparent border-r-[6px] border-r-transparent border-t-[6px] border-t-[#0B1B23]" />
          </div>
        )}
        <svg
          viewBox="0 0 32 32"
          className={`${currentSize.class} cursor-pointer drop-shadow-[0_10px_20px_rgba(61,220,132,0.3)] transition-transform duration-200 hover:scale-105 ${wobble ? 'anim-wobble' : ''}`}
          onClick={handleClick}
          shapeRendering="crispEdges"
        >
          {/* Crown */}
          <rect x="12" y="3" width="2" height="4" fill="#FFC857" />
          <rect x="15" y="1" width="2" height="6" fill="#FFC857" />
          <rect x="18" y="3" width="2" height="4" fill="#FFC857" />
          <rect x="11" y="6" width="10" height="2" fill="#FFC857" />
          
          {/* Monitor Outline & Shell */}
          <rect x="6" y="7" width="20" height="18" fill="#0B1B23" rx="2" />
          <rect x="7" y="8" width="18" height="16" fill="#F4F1E9" />
          
          {/* Screen */}
          <rect x="9" y="10" width="14" height="11" fill="#0B1B23" />
          <rect x="10" y="11" width="12" height="9" fill="#071015" />
          
          {/* Screen Eyes & Smile in Green */}
          {currentExp === 'confused' ? (
            <>
              <rect x="11" y="13" width="2" height="2" fill="#3DDC84" />
              <rect x="18" y="14" width="2" height="2" fill="#3DDC84" />
              <rect x="13" y="17" width="5" height="1" fill="#3DDC84" />
            </>
          ) : currentExp === 'surprised' ? (
            <>
              <rect x="12" y="13" width="2" height="3" fill="#3DDC84" />
              <rect x="18" y="13" width="2" height="3" fill="#3DDC84" />
              <rect x="15" y="16" width="2" height="2" fill="#3DDC84" />
            </>
          ) : isBlinking ? (
            <>
              <rect x="11" y="14" width="3" height="1" fill="#3DDC84" />
              <rect x="18" y="14" width="3" height="1" fill="#3DDC84" />
            </>
          ) : (
            <>
              <rect x="12" y="13" width="2" height="2" fill="#3DDC84" />
              <rect x="18" y="13" width="2" height="2" fill="#3DDC84" />
              <rect x="13" y="17" width="1" height="1" fill="#3DDC84" />
              <rect x="14" y="18" width="4" height="1" fill="#3DDC84" />
              <rect x="18" y="17" width="1" height="1" fill="#3DDC84" />
            </>
          )}

          {/* Controller */}
          <rect x="10" y="24" width="12" height="5" fill="#0B1B23" rx="2" />
          <rect x="11" y="25" width="10" height="3" fill="#E6DFCF" />
          {/* Dpad */}
          <rect x="12" y="26" width="2" height="1" fill="#0B1B23" />
          {/* Red Buttons */}
          <rect x="17" y="26" width="1" height="1" fill="#FF4B3A" />
          <rect x="19" y="26" width="1" height="1" fill="#FF4B3A" />

          {/* Feet */}
          <rect x="9" y="28" width="4" height="3" fill="#0B1B23" />
          <rect x="19" y="28" width="4" height="3" fill="#0B1B23" />
        </svg>
      </div>
    );
  }

  // High-Fidelity Vector CRT Fried
  return (
    <div
      className={`relative inline-flex flex-col items-center select-none ${interactive ? 'cursor-pointer' : ''} ${className}`}
      onClick={handleClick}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      {/* Speech Bubble */}
      {speechBubble && (
        <div className="absolute -top-16 left-1/2 -translate-x-1/2 z-30 max-w-[280px] bg-[#F6F2E9] text-[#0B1B23] border-[2.5px] border-[#0B1B23] px-3.5 py-2 rounded-2xl shadow-xl font-sans text-xs md:text-sm font-bold text-center animate-bounce flex items-center gap-1.5">
          <span>{speechBubble}</span>
          <div className="absolute -bottom-2.5 left-1/2 -translate-x-1/2 w-0 h-0 border-l-[8px] border-l-transparent border-r-[8px] border-r-transparent border-t-[8px] border-t-[#0B1B23]" />
        </div>
      )}

      <div className={`relative ${currentSize.class} transition-transform duration-300 ${wobble ? 'scale-110 rotate-3' : 'hover:scale-105'}`}>
        <svg
          viewBox="0 0 240 240"
          className="w-full h-full overflow-visible"
        >
          <defs>
            {/* Screen Gradient & Glow */}
            <radialGradient id={id("screenGlow")} cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#1B3848" />
              <stop offset="85%" stopColor="#0B1B23" />
              <stop offset="100%" stopColor="#071015" />
            </radialGradient>

            <filter id={id("pixelGreenGlow")} x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>

            <filter id={id("crownShine")} x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="2" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>

            {/* Subtle CRT Scanlines pattern inside monitor */}
            <pattern id={id("scanlines")} width="100" height="4" patternUnits="userSpaceOnUse">
              <line x1="0" y1="0" x2="100" y2="0" stroke="rgba(0,0,0,0.25)" strokeWidth="1" />
            </pattern>
          </defs>

          {/* Back cable connection if enabled */}
          {showCable && (
            <path
              d="M 52 135 C 20 135, 10 160, 25 185 C 35 195, 45 195, 60 190"
              fill="none"
              stroke="#0B1B23"
              strokeWidth="6"
              strokeLinecap="round"
            />
          )}

          {/* Shadow */}
          <ellipse cx="120" cy="225" rx="72" ry="12" fill="rgba(0,0,0,0.22)" />

          {/* Feet */}
          <g data-part="feet">
            {/* Left Foot */}
            <path
              d="M 75 195 C 62 195, 55 208, 62 220 C 68 226, 85 226, 92 220 C 96 210, 90 195, 75 195 Z"
              fill="#0B1B23"
            />
            {/* Right Foot */}
            <path
              d="M 165 195 C 150 195, 144 210, 148 220 C 155 226, 172 226, 178 220 C 185 208, 178 195, 165 195 Z"
              fill="#0B1B23"
            />
          </g>

          {/* CRT Monitor Outer Casing */}
          <g data-part="monitor-body">
            {/* Outer Dark Border Shell */}
            <rect
              x="38"
              y="40"
              width="164"
              height="146"
              rx="34"
              fill="#0B1B23"
            />
            {/* White/Cream Retro Housing */}
            <rect
              x="44"
              y="46"
              width="152"
              height="134"
              rx="28"
              fill="#F4F1E9"
            />
            {/* Inner Screen Bezel */}
            <rect
              x="56"
              y="58"
              width="128"
              height="108"
              rx="20"
              fill="#0B1B23"
            />
            {/* CRT Screen Surface */}
            <rect
              x="62"
              y="64"
              width="116"
              height="96"
              rx="16"
              fill={`url(#${id("screenGlow")})`}
            />
            {/* Scanlines overlay on screen */}
            <rect
              x="62"
              y="64"
              width="116"
              height="96"
              rx="16"
              fill={`url(#${id("scanlines")})`}
              opacity="0.4"
            />
            {/* Glass Corner Glare Accent */}
            <path
              d="M 68 72 C 78 72, 95 76, 105 84 C 95 82, 80 82, 70 88 C 68 84, 68 76, 68 72 Z"
              fill="rgba(255,255,255,0.18)"
            />
          </g>

          {/* Golden Crown on Top */}
          <g data-part="crown" filter={`url(#${id("crownShine")})`}>
            {/* Crown base & spikes */}
            <path
              d="M 98 42 L 86 18 L 108 26 L 120 10 L 132 26 L 154 18 L 142 42 Z"
              fill="#FFC857"
              stroke="#0B1B23"
              strokeWidth="4"
              strokeLinejoin="round"
            />
            {/* Crown Gem highlights */}
            <circle cx="120" cy="24" r="3" fill="#FF4B3A" />
            <circle cx="100" cy="30" r="2.5" fill="#3DDC84" />
            <circle cx="140" cy="30" r="2.5" fill="#3DDC84" />
          </g>

          {/* Screen Expressions (Pixel Green) */}
          <g data-part="face" filter={glow ? `url(#${id("pixelGreenGlow")})` : undefined}>
            {/* Eye blinking logic */}
            {isBlinking ? (
              <g stroke="#3DDC84" strokeWidth="4.5" strokeLinecap="round">
                <line x1="84" y1="102" x2="100" y2="102" />
                <line x1="140" y1="102" x2="156" y2="102" />
              </g>
            ) : currentExp === 'friendly' ? (
              <>
                {/* Standard Friendly Eyes */}
                <rect x="86" y="94" width="12" height="15" rx="3" fill="#3DDC84" />
                <rect x="142" y="94" width="12" height="15" rx="3" fill="#3DDC84" />
                {/* Pixel Smile */}
                <path
                  d="M 92 124 Q 120 144 148 124"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="5"
                  strokeLinecap="round"
                />
              </>
            ) : currentExp === 'winking' ? (
              <>
                {/* Left eye open, right eye wink */}
                <rect x="86" y="94" width="12" height="15" rx="3" fill="#3DDC84" />
                <path
                  d="M 140 102 L 148 94 L 156 102"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="4.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
                <path
                  d="M 92 122 Q 120 146 148 122"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="5"
                  strokeLinecap="round"
                />
              </>
            ) : currentExp === 'surprised' ? (
              <>
                {/* Wide eyes and open mouth */}
                <rect x="84" y="90" width="14" height="20" rx="4" fill="#3DDC84" />
                <rect x="142" y="90" width="14" height="20" rx="4" fill="#3DDC84" />
                <circle cx="120" cy="130" r="9" fill="#3DDC84" />
              </>
            ) : currentExp === 'happy' ? (
              <>
                {/* Curved Happy Eyes */}
                <path
                  d="M 82 102 C 86 90, 102 90, 106 102"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="5"
                  strokeLinecap="round"
                />
                <path
                  d="M 134 102 C 138 90, 154 90, 158 102"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="5"
                  strokeLinecap="round"
                />
                {/* Big happy open mouth */}
                <path
                  d="M 90 120 C 90 142, 150 142, 150 120 Z"
                  fill="#3DDC84"
                />
              </>
            ) : currentExp === 'neutral' ? (
              <>
                {/* Focused/Thinking Eyes */}
                <rect x="86" y="98" width="14" height="9" rx="2" fill="#3DDC84" />
                <rect x="140" y="98" width="14" height="9" rx="2" fill="#3DDC84" />
                {/* Straight mouth */}
                <line x1="102" y1="130" x2="138" y2="130" stroke="#3DDC84" strokeWidth="4.5" strokeLinecap="round" />
              </>
            ) : (
              /* Confused */
              <>
                {/* Asymmetric eyes */}
                <rect x="84" y="92" width="14" height="12" rx="3" fill="#3DDC84" />
                <rect x="142" y="102" width="12" height="14" rx="3" fill="#3DDC84" />
                {/* Squiggly mouth */}
                <path
                  d="M 96 130 Q 110 124, 120 132 T 144 126"
                  fill="none"
                  stroke="#3DDC84"
                  strokeWidth="4"
                  strokeLinecap="round"
                />
                {/* Tiny pixel question mark */}
                <text x="156" y="85" fill="#3DDC84" fontSize="16" fontWeight="bold" fontFamily="monospace">?</text>
              </>
            )}
          </g>

          {/* Poses: Hands, Controllers, Laptop */}
          {pose === 'controller' && (
            <g data-part="pose-controller">
              {/* Retro Gamepad Body */}
              <rect
                x="62"
                y="160"
                width="116"
                height="46"
                rx="23"
                fill="#F4F1E9"
                stroke="#0B1B23"
                strokeWidth="5"
              />
              {/* D-Pad (Cross) */}
              <g fill="#0B1B23">
                <rect x="82" y="173" width="20" height="7" rx="1.5" />
                <rect x="88.5" y="166.5" width="7" height="20" rx="1.5" />
                <circle cx="92" cy="176.5" r="1.5" fill="#718096" />
              </g>
              {/* Center Menu Pill Buttons */}
              <rect x="111" y="181" width="8" height="3.5" rx="1.5" fill="#718096" transform="rotate(-25 111 181)" />
              <rect x="122" y="181" width="8" height="3.5" rx="1.5" fill="#718096" transform="rotate(-25 122 181)" />
              {/* Red Action Buttons */}
              <circle cx="146" cy="184" r="5.5" fill="#FF4B3A" stroke="#0B1B23" strokeWidth="1.5" />
              <circle cx="158" cy="173" r="5.5" fill="#FF4B3A" stroke="#0B1B23" strokeWidth="1.5" />

              {/* Fried's Hands holding controller */}
              <circle cx="64" cy="180" r="13" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4.5" />
              <circle cx="176" cy="180" r="13" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4.5" />
            </g>
          )}

          {pose === 'thumbs-up' && (
            <g data-part="pose-thumbs-up">
              {/* Left hand holding side */}
              <circle cx="48" cy="165" r="12" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4.5" />
              {/* Right hand giving big thumbs up */}
              <g transform="translate(165, 140)">
                <circle cx="18" cy="22" r="12" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4" />
                {/* Thumb pointing up */}
                <rect x="12" y="2" width="10" height="20" rx="5" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4" />
                {/* Green sparkle */}
                <path d="M 28 0 L 32 -6 L 36 0 L 32 6 Z" fill="#3DDC84" />
              </g>
            </g>
          )}

          {pose === 'laptop' && (
            <g data-part="pose-laptop">
              {/* Small sleek agent laptop */}
              <rect x="68" y="172" width="104" height="12" rx="3" fill="#1C3341" stroke="#0B1B23" strokeWidth="3" />
              <path
                d="M 80 172 L 95 138 L 145 138 L 160 172 Z"
                fill="#0B1B23"
                stroke="#0B1B23"
                strokeWidth="2"
              />
              {/* Golden Crown badge on laptop lid */}
              <path
                d="M 115 156 L 111 146 L 117 150 L 120 142 L 123 150 L 129 146 L 125 156 Z"
                fill="#FFC857"
              />
              {/* Hands on keyboard */}
              <circle cx="78" cy="176" r="8" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="3.5" />
              <circle cx="162" cy="176" r="8" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="3.5" />
            </g>
          )}

          {pose === 'celebrate' && (
            <g data-part="pose-celebrate">
              {/* Arms raised up in victory */}
              <path d="M 45 150 Q 25 120 30 100" fill="none" stroke="#0B1B23" strokeWidth="12" strokeLinecap="round" />
              <circle cx="30" cy="100" r="10" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4" />

              <path d="M 195 150 Q 215 120 210 100" fill="none" stroke="#0B1B23" strokeWidth="12" strokeLinecap="round" />
              <circle cx="210" cy="100" r="10" fill="#F4F1E9" stroke="#0B1B23" strokeWidth="4" />

              {/* Sparkles around */}
              <path d="M 20 60 L 25 50 L 30 60 L 25 70 Z" fill="#FFC857" />
              <path d="M 215 60 L 220 50 L 225 60 L 220 70 Z" fill="#3DDC84" />
              <circle cx="45" cy="40" r="3" fill="#FF4B3A" />
              <circle cx="195" cy="40" r="3" fill="#FFC857" />
            </g>
          )}
        </svg>
      </div>

    </div>
  );
};
